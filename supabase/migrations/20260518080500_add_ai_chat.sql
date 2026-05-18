-- Persistent AI chat threads, messages, and image attachment storage

CREATE TABLE IF NOT EXISTS public.chat_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_chat_threads_user_updated
ON public.chat_threads(user_id, updated_at DESC);

DROP POLICY IF EXISTS "Users can view their own chat threads" ON public.chat_threads;
DROP POLICY IF EXISTS "Users can insert their own chat threads" ON public.chat_threads;
DROP POLICY IF EXISTS "Users can update their own chat threads" ON public.chat_threads;

CREATE POLICY "Users can view their own chat threads"
ON public.chat_threads FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own chat threads"
ON public.chat_threads FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own chat threads"
ON public.chat_threads FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID REFERENCES public.chat_threads(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
  content TEXT,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  tool_calls JSONB NOT NULL DEFAULT '[]'::jsonb,
  tool_results JSONB NOT NULL DEFAULT '[]'::jsonb,
  pending_action JSONB,
  action_status TEXT CHECK (action_status IN ('pending', 'approved', 'rejected', 'executed', 'failed')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_created
ON public.chat_messages(thread_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_messages_user_created
ON public.chat_messages(user_id, created_at DESC);

DROP POLICY IF EXISTS "Users can view their own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can insert their own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update their own chat messages" ON public.chat_messages;

CREATE POLICY "Users can view their own chat messages"
ON public.chat_messages FOR SELECT
USING (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.chat_threads
    WHERE chat_threads.id = chat_messages.thread_id
      AND chat_threads.user_id = auth.uid()
  )
);

CREATE POLICY "Users can insert their own chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.chat_threads
    WHERE chat_threads.id = chat_messages.thread_id
      AND chat_threads.user_id = auth.uid()
  )
);

CREATE POLICY "Users can update their own chat messages"
ON public.chat_messages FOR UPDATE
USING (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.chat_threads
    WHERE chat_threads.id = chat_messages.thread_id
      AND chat_threads.user_id = auth.uid()
  )
)
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.chat_threads
    WHERE chat_threads.id = chat_messages.thread_id
      AND chat_threads.user_id = auth.uid()
  )
);

CREATE OR REPLACE FUNCTION public.touch_chat_thread_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.chat_threads
  SET updated_at = now()
  WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_touch_chat_thread_updated_at ON public.chat_messages;
CREATE TRIGGER trg_touch_chat_thread_updated_at
AFTER INSERT OR UPDATE ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.touch_chat_thread_updated_at();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments',
  'chat-attachments',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload their own chat attachments" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own chat attachments" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own chat attachments" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own chat attachments" ON storage.objects;

CREATE POLICY "Users can upload their own chat attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can view their own chat attachments"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can update their own chat attachments"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can delete their own chat attachments"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
