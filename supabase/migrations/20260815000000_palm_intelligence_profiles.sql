-- Phase 1: Palm Intelligence Profiles
-- Stores the structured palm intelligence profile derived from Stage A.
-- Stage B generates the personalized reading narrative from this profile,
-- not from a generic prompt, ensuring two different palms produce different readings.

CREATE TABLE IF NOT EXISTS public.palm_intelligence_profiles (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id             UUID NOT NULL REFERENCES public.palm_scans(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  analysis_id         UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,

  -- Structured signal groups extracted from Stage A
  -- Each group: { signal, observation, interpretation, life_area, confidence }
  life_line_signals   JSONB NOT NULL DEFAULT '[]'::jsonb,
  head_line_signals   JSONB NOT NULL DEFAULT '[]'::jsonb,
  heart_line_signals  JSONB NOT NULL DEFAULT '[]'::jsonb,
  fate_line_signals   JSONB NOT NULL DEFAULT '[]'::jsonb,
  sun_line_signals    JSONB NOT NULL DEFAULT '[]'::jsonb,
  mercury_line_signals JSONB NOT NULL DEFAULT '[]'::jsonb,
  mount_signals       JSONB NOT NULL DEFAULT '[]'::jsonb,
  special_mark_signals JSONB NOT NULL DEFAULT '[]'::jsonb,
  palm_shape_signals  JSONB NOT NULL DEFAULT '[]'::jsonb,

  -- Aggregated life-area interpretations derived from signals
  -- Keys: career, money, relationships, health, personality, future, strengths, challenges
  life_area_interpretations JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Overall profile metadata
  overall_confidence  NUMERIC(4,2) NOT NULL DEFAULT 0.70,
  signal_count        INTEGER NOT NULL DEFAULT 0,
  profile_version     TEXT NOT NULL DEFAULT '1.0',

  -- Raw Stage A output preserved for debugging / re-generation
  raw_stage_a         JSONB,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_palm_intelligence_profiles_scan_id
  ON public.palm_intelligence_profiles(scan_id);

CREATE INDEX IF NOT EXISTS idx_palm_intelligence_profiles_user_id
  ON public.palm_intelligence_profiles(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_palm_intelligence_profiles_scan_unique
  ON public.palm_intelligence_profiles(scan_id);

-- RLS
ALTER TABLE public.palm_intelligence_profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profiles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'palm_intelligence_profiles'
      AND policyname = 'Users can read own palm intelligence profiles'
  ) THEN
    CREATE POLICY "Users can read own palm intelligence profiles"
      ON public.palm_intelligence_profiles
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Service role writes (Edge Function uses service role key)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'palm_intelligence_profiles'
      AND policyname = 'Service role can manage palm intelligence profiles'
  ) THEN
    CREATE POLICY "Service role can manage palm intelligence profiles"
      ON public.palm_intelligence_profiles
      FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Grant permissions
GRANT SELECT ON public.palm_intelligence_profiles TO authenticated;
GRANT ALL ON public.palm_intelligence_profiles TO service_role;
