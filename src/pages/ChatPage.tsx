import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { format } from "date-fns";
import { Bot, ImagePlus, Loader2, RefreshCw, Send, Trash2, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import { AppLayout } from "@/components/layout/AppLayout";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { cn } from "@/lib/utils";
import { useToast } from "@/hooks/use-toast";

type ChatRole = "user" | "assistant" | "system" | "tool";

type ChatAttachment = {
  path: string;
  name: string;
  type: string;
  size: number;
  signedUrl?: string;
};

type ChatMessage = {
  id: string;
  thread_id: string;
  user_id: string;
  role: ChatRole;
  content: string | null;
  attachments: ChatAttachment[];
  tool_calls: Array<{ id?: string; name?: string; arguments?: Record<string, unknown> }>;
  tool_results: Array<{ id?: string; name?: string; summary?: string; result?: unknown }>;
  created_at: string;
  deleted_at?: string | null;
};

const PAGE_SIZE = 10;

const renderInlineMarkdown = (text: string) => {
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((part, index) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={index} className="font-semibold text-foreground">{part.slice(2, -2)}</strong>;
    }
    return <span key={index}>{part}</span>;
  });
};

const renderAssistantContent = (content: string) => {
  const lines = content.split("\n");
  const blocks: JSX.Element[] = [];
  let listItems: string[] = [];

  const flushList = () => {
    if (!listItems.length) return;
    blocks.push(
      <ul key={`list-${blocks.length}`} className="my-3 space-y-2 pl-1">
        {listItems.map((item, index) => (
          <li key={index} className="flex gap-2 leading-relaxed">
            <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-primary" />
            <span>{renderInlineMarkdown(item)}</span>
          </li>
        ))}
      </ul>
    );
    listItems = [];
  };

  lines.forEach((line) => {
    const trimmed = line.trim();
    if (!trimmed) {
      flushList();
      return;
    }

    const bulletMatch = trimmed.match(/^[*-]\s+(.+)$/);
    if (bulletMatch) {
      listItems.push(bulletMatch[1]);
      return;
    }

    flushList();
    blocks.push(
      <p key={`p-${blocks.length}`} className="my-2 leading-relaxed">
        {renderInlineMarkdown(trimmed)}
      </p>
    );
  });

  flushList();
  return <div className="space-y-1 text-[15px] leading-relaxed">{blocks}</div>;
};

const ChatPage = () => {
  const { t, i18n } = useTranslation();
  const { user } = useAuth();
  const { toast } = useToast();
  const [threadId, setThreadId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const sortedMessages = useMemo(
    () => [...messages].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()),
    [messages]
  );

  const welcomeMessage = useMemo<ChatMessage>(() => ({
    id: "welcome",
    thread_id: threadId || "welcome",
    user_id: user?.id || "system",
    role: "assistant",
    content: t("chat.welcomeMessage"),
    attachments: [],
    tool_calls: [],
    tool_results: [],
    created_at: new Date().toISOString(),
  }), [t, threadId, user?.id]);

  const visibleMessages = sortedMessages.length ? sortedMessages : [welcomeMessage];

  const scrollToBottom = useCallback((behavior: ScrollBehavior = "auto") => {
    requestAnimationFrame(() => {
      const el = scrollRef.current;
      if (!el) return;
      el.scrollTo({ top: el.scrollHeight, behavior });
    });
  }, []);

  const signAttachments = useCallback(async (items: ChatMessage[]) => {
    return Promise.all(items.map(async (message) => {
      const attachments = await Promise.all((message.attachments || []).map(async (attachment) => {
        const { data } = await supabase.storage.from("chat-attachments").createSignedUrl(attachment.path, 60 * 60);
        return { ...attachment, signedUrl: data?.signedUrl };
      }));
      return { ...message, attachments };
    }));
  }, []);

  const ensureThread = useCallback(async () => {
    if (!user) return null;

    const { data: existing, error: existingError } = await supabase
      .from("chat_threads" as any)
      .select("id")
      .eq("user_id", user.id)
      .is("archived_at", null)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingError) throw existingError;
    const existingThread = existing as unknown as { id?: string } | null;
    if (existingThread?.id) return existingThread.id;

    const { data: created, error: createError } = await supabase
      .from("chat_threads" as any)
      .insert({ user_id: user.id, title: t("chat.newThread") })
      .select("id")
      .single();

    if (createError) throw createError;
    return (created as unknown as { id: string }).id;
  }, [t, user]);

  const loadInitial = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      const activeThreadId = await ensureThread();
      if (!activeThreadId) return;
      setThreadId(activeThreadId);
      const { data, error } = await supabase
        .from("chat_messages" as any)
        .select("*")
        .eq("thread_id", activeThreadId)
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(PAGE_SIZE);

      if (error) throw error;
      const signed = await signAttachments((data || []) as unknown as ChatMessage[]);
      setMessages(signed.reverse());
      setHasMore((data || []).length === PAGE_SIZE);
      scrollToBottom();
    } catch (error) {
      console.error(error);
      toast({ title: t("common.error"), description: t("chat.errors.load"), variant: "destructive" });
    } finally {
      setLoading(false);
    }
  }, [ensureThread, scrollToBottom, signAttachments, t, toast, user]);

  const loadMore = useCallback(async () => {
    if (!threadId || !user || loadingMore || !hasMore || !messages.length) return;
    const el = scrollRef.current;
    const oldHeight = el?.scrollHeight || 0;
    setLoadingMore(true);
    try {
      const oldest = sortedMessages[0];
      const { data, error } = await supabase
        .from("chat_messages" as any)
        .select("*")
        .eq("thread_id", threadId)
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .lt("created_at", oldest.created_at)
        .order("created_at", { ascending: false })
        .limit(PAGE_SIZE);

      if (error) throw error;
      const signed = await signAttachments((data || []) as unknown as ChatMessage[]);
      setMessages((prev) => [...signed.reverse(), ...prev]);
      setHasMore((data || []).length === PAGE_SIZE);
      requestAnimationFrame(() => {
        if (!el) return;
        el.scrollTop = el.scrollHeight - oldHeight;
      });
    } catch (error) {
      console.error(error);
      toast({ title: t("common.error"), description: t("chat.errors.loadMore"), variant: "destructive" });
    } finally {
      setLoadingMore(false);
    }
  }, [hasMore, loadingMore, messages.length, signAttachments, sortedMessages, t, threadId, toast, user]);

  useEffect(() => {
    loadInitial();
  }, [loadInitial]);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop < 80) loadMore();
  };

  const uploadAttachments = async (activeThreadId: string) => {
    if (!user || !selectedFiles.length) return [];
    const uploaded: ChatAttachment[] = [];
    for (const file of selectedFiles) {
      const extension = file.name.split(".").pop() || "jpg";
      const path = `${user.id}/${activeThreadId}/${crypto.randomUUID()}.${extension}`;
      const { error } = await supabase.storage.from("chat-attachments").upload(path, file, { contentType: file.type, upsert: false });
      if (error) throw error;
      const { data } = await supabase.storage.from("chat-attachments").createSignedUrl(path, 60 * 60);
      uploaded.push({ path, name: file.name, type: file.type, size: file.size, signedUrl: data?.signedUrl });
    }
    return uploaded;
  };

  const invokeAssistant = async (activeThreadId: string) => {
    const { data, error } = await supabase.functions.invoke("ai-chat", {
      body: {
        mode: "chat",
        threadId: activeThreadId,
        locale: navigator.language || i18n.language,
        language: i18n.language,
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        currentDate: new Date().toLocaleDateString("en-CA"),
      },
    });
    if (error) throw error;
    if (data?.message) {
      const signed = await signAttachments([data.message as ChatMessage]);
      setMessages((prev) => [...prev, signed[0]]);
      scrollToBottom("smooth");
    }
  };

  const sendMessage = async () => {
    if (!user || !threadId || sending || (!input.trim() && !selectedFiles.length)) return;
    setSending(true);
    try {
      const attachments = await uploadAttachments(threadId);
      const { data: saved, error } = await supabase
        .from("chat_messages" as any)
        .insert({
          thread_id: threadId,
          user_id: user.id,
          role: "user",
          content: input.trim() || null,
          attachments,
        })
        .select("*")
        .single();

      if (error) throw error;
      setMessages((prev) => [...prev, saved as unknown as ChatMessage]);
      setInput("");
      setSelectedFiles([]);
      scrollToBottom("smooth");
      await invokeAssistant(threadId);
    } catch (error) {
      console.error(error);
      toast({ title: t("common.error"), description: t("chat.errors.send"), variant: "destructive" });
    } finally {
      setSending(false);
    }
  };

  const clearVisibleChat = async () => {
    if (!threadId) return;
    try {
      await supabase.from("chat_threads" as any).update({ archived_at: new Date().toISOString() }).eq("id", threadId);
      setMessages([]);
      setThreadId(null);
      await loadInitial();
    } catch (error) {
      console.error(error);
      toast({ title: t("common.error"), description: t("chat.errors.clear"), variant: "destructive" });
    }
  };

  return (
    <AppLayout title={t("chat.title")}>
      <div className="container flex h-[calc(100vh-8.5rem)] max-w-lg flex-col px-4 py-3">
        <div className="mb-3 flex items-center justify-between">
          <div>
            <p className="text-sm text-muted-foreground">{t("chat.subtitle")}</p>
          </div>
          <Button variant="ghost" size="icon" onClick={clearVisibleChat} title={t("chat.clear")}>
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>

        <div ref={scrollRef} onScroll={handleScroll} className="min-h-0 flex-1 space-y-3 overflow-y-auto rounded-xl border border-border bg-card/30 p-3">
          {loading ? (
            <div className="space-y-3">
              <Skeleton className="h-16 w-3/4" />
              <Skeleton className="ml-auto h-16 w-3/4" />
              <Skeleton className="h-24 w-4/5" />
            </div>
          ) : (
            <>
              {loadingMore && <div className="flex justify-center"><RefreshCw className="h-4 w-4 animate-spin text-muted-foreground" /></div>}
              {!sortedMessages.length && (
                <div className="flex justify-center py-2 text-center text-xs text-muted-foreground">
                  <span>{t("chat.emptyDesc")}</span>
                </div>
              )}
              {visibleMessages.map((message) => {
                const isUser = message.role === "user";
                return (
                  <div key={message.id} className={cn("flex", isUser ? "justify-end" : "justify-start")}>
                    <div className={cn("max-w-[86%] rounded-2xl px-3 py-2 text-sm shadow-sm", isUser ? "bg-primary text-primary-foreground" : "bg-card text-card-foreground border border-border")}>
                      {!isUser && <div className="mb-1 flex items-center gap-1 text-xs text-primary"><Bot className="h-3 w-3" /> CaloriX AI</div>}
                      {message.content && (
                        isUser
                          ? <p className="whitespace-pre-wrap leading-relaxed">{message.content}</p>
                          : renderAssistantContent(message.content)
                      )}
                      {!!message.attachments?.length && (
                        <div className="mt-2 grid grid-cols-2 gap-2">
                          {message.attachments.map((attachment) => (
                            <img key={attachment.path} src={attachment.signedUrl} alt={attachment.name} className="h-28 rounded-lg object-cover" />
                          ))}
                        </div>
                      )}
                      <p className={cn("mt-1 text-[10px]", isUser ? "text-primary-foreground/70" : "text-muted-foreground")}>
                        {format(new Date(message.created_at), "HH:mm")}
                      </p>
                    </div>
                  </div>
                );
              })}
              {sending && <div className="flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />{t("chat.thinking")}</div>}
            </>
          )}
        </div>

        {!!selectedFiles.length && (
          <div className="mt-2 flex gap-2 overflow-x-auto">
            {selectedFiles.map((file, index) => (
              <Badge key={`${file.name}-${index}`} variant="secondary" className="gap-1 whitespace-nowrap">
                {file.name}
                <button onClick={() => setSelectedFiles((prev) => prev.filter((_, i) => i !== index))}><X className="h-3 w-3" /></button>
              </Badge>
            ))}
          </div>
        )}

        <div className="mt-3 flex items-center gap-2 rounded-2xl border border-border bg-card/80 p-2 shadow-lg backdrop-blur">
          <input
            ref={fileInputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp,image/gif"
            multiple
            className="hidden"
            onChange={(event) => setSelectedFiles(Array.from(event.target.files || []))}
          />
          <Button
            variant="ghost"
            size="icon"
            className="h-11 w-11 shrink-0 rounded-xl text-muted-foreground hover:text-foreground"
            onClick={() => fileInputRef.current?.click()}
            disabled={sending}
          >
            <ImagePlus className="h-4 w-4" />
          </Button>
          <Textarea
            value={input}
            rows={1}
            onChange={(event) => setInput(event.target.value)}
            placeholder={t("chat.placeholder")}
            className="h-11 min-h-0 flex-1 resize-none rounded-xl border-0 bg-muted/60 px-3 py-3 leading-5 shadow-none focus-visible:ring-1 focus-visible:ring-primary focus-visible:ring-offset-0"
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                sendMessage();
              }
            }}
          />
          <Button
            size="icon"
            className="h-11 w-11 shrink-0 rounded-xl shadow-sm"
            onClick={sendMessage}
            disabled={sending || (!input.trim() && !selectedFiles.length)}
          >
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </Button>
        </div>
      </div>
    </AppLayout>
  );
};

export default ChatPage;
