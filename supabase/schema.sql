-- ============================================================================
-- HydraScraper PostgreSQL Schema
-- Created: 2026-01-05 14:03:22 UTC
-- Database: Supabase PostgreSQL
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- ENUMS AND TYPES
-- ============================================================================

CREATE TYPE public.scrape_status AS ENUM (
    'pending',
    'running',
    'completed',
    'failed',
    'paused',
    'cancelled'
);

CREATE TYPE public.error_severity AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'moderator',
    'user',
    'viewer'
);

-- ============================================================================
-- TABLES
-- ============================================================================

-- Users table
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    auth_id UUID UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    role public.user_role DEFAULT 'user'::public.user_role,
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Projects table
CREATE TABLE IF NOT EXISTS public.projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    url TEXT NOT NULL,
    is_public BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT projects_user_id_name_unique UNIQUE(user_id, name)
);

-- Scrape jobs table
CREATE TABLE IF NOT EXISTS public.scrape_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    status public.scrape_status DEFAULT 'pending'::public.scrape_status,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Scrape results table
CREATE TABLE IF NOT EXISTS public.scrape_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES public.scrape_jobs(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    status_code INT,
    response_time_ms INT,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_content TEXT,
    content_type TEXT,
    page_title TEXT,
    meta_description TEXT,
    headers JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Errors log table
CREATE TABLE IF NOT EXISTS public.error_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID REFERENCES public.scrape_jobs(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    error_stack TEXT,
    severity public.error_severity DEFAULT 'medium'::public.error_severity,
    context JSONB DEFAULT '{}'::jsonb,
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Activity logs table
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    resource_type TEXT,
    resource_id UUID,
    changes JSONB DEFAULT '{}'::jsonb,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- API keys table
CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Schedules table
CREATE TABLE IF NOT EXISTS public.schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    cron_expression TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true,
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    configuration JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT schedules_project_id_name_unique UNIQUE(project_id, name)
);

-- Data storage table
CREATE TABLE IF NOT EXISTS public.data_storage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    data_type TEXT NOT NULL,
    key TEXT NOT NULL,
    value JSONB NOT NULL DEFAULT '{}'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT data_storage_project_key_unique UNIQUE(project_id, key)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT,
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,
    data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDICES
-- ============================================================================

-- Users indices
CREATE INDEX idx_users_auth_id ON public.users(auth_id);
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_users_is_active ON public.users(is_active);
CREATE INDEX idx_users_created_at ON public.users(created_at DESC);

-- Projects indices
CREATE INDEX idx_projects_user_id ON public.projects(user_id);
CREATE INDEX idx_projects_is_active ON public.projects(is_active);
CREATE INDEX idx_projects_is_public ON public.projects(is_public);
CREATE INDEX idx_projects_created_at ON public.projects(created_at DESC);
CREATE INDEX idx_projects_user_id_active ON public.projects(user_id, is_active);

-- Scrape jobs indices
CREATE INDEX idx_scrape_jobs_project_id ON public.scrape_jobs(project_id);
CREATE INDEX idx_scrape_jobs_status ON public.scrape_jobs(status);
CREATE INDEX idx_scrape_jobs_created_at ON public.scrape_jobs(created_at DESC);
CREATE INDEX idx_scrape_jobs_project_status ON public.scrape_jobs(project_id, status);
CREATE INDEX idx_scrape_jobs_scheduled_at ON public.scrape_jobs(scheduled_at) WHERE status = 'pending'::public.scrape_status;

-- Scrape results indices
CREATE INDEX idx_scrape_results_job_id ON public.scrape_results(job_id);
CREATE INDEX idx_scrape_results_project_id ON public.scrape_results(project_id);
CREATE INDEX idx_scrape_results_url ON public.scrape_results(url);
CREATE INDEX idx_scrape_results_created_at ON public.scrape_results(created_at DESC);
CREATE INDEX idx_scrape_results_status_code ON public.scrape_results(status_code);
CREATE INDEX idx_scrape_results_job_created ON public.scrape_results(job_id, created_at DESC);

-- Error logs indices
CREATE INDEX idx_error_logs_job_id ON public.error_logs(job_id);
CREATE INDEX idx_error_logs_project_id ON public.error_logs(project_id);
CREATE INDEX idx_error_logs_severity ON public.error_logs(severity);
CREATE INDEX idx_error_logs_created_at ON public.error_logs(created_at DESC);
CREATE INDEX idx_error_logs_resolved ON public.error_logs(resolved);

-- Activity logs indices
CREATE INDEX idx_activity_logs_user_id ON public.activity_logs(user_id);
CREATE INDEX idx_activity_logs_project_id ON public.activity_logs(project_id);
CREATE INDEX idx_activity_logs_created_at ON public.activity_logs(created_at DESC);
CREATE INDEX idx_activity_logs_resource ON public.activity_logs(resource_type, resource_id);

-- API keys indices
CREATE INDEX idx_api_keys_user_id ON public.api_keys(user_id);
CREATE INDEX idx_api_keys_is_active ON public.api_keys(is_active);
CREATE INDEX idx_api_keys_created_at ON public.api_keys(created_at DESC);

-- Schedules indices
CREATE INDEX idx_schedules_project_id ON public.schedules(project_id);
CREATE INDEX idx_schedules_is_active ON public.schedules(is_active);
CREATE INDEX idx_schedules_next_run ON public.schedules(next_run_at) WHERE is_active = true;

-- Data storage indices
CREATE INDEX idx_data_storage_project_id ON public.data_storage(project_id);
CREATE INDEX idx_data_storage_key ON public.data_storage(key);
CREATE INDEX idx_data_storage_project_key ON public.data_storage(project_id, key);

-- Notifications indices
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_created_at ON public.notifications(created_at DESC);
CREATE INDEX idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX idx_notifications_user_read ON public.notifications(user_id, is_read);

-- Full-text search indices
CREATE INDEX idx_scrape_results_data_gin ON public.scrape_results USING GIN(data);
CREATE INDEX idx_error_logs_context_gin ON public.error_logs USING GIN(context);
CREATE INDEX idx_projects_config_gin ON public.projects USING GIN(config);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: users updated_at
CREATE TRIGGER trigger_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: projects updated_at
CREATE TRIGGER trigger_projects_updated_at
BEFORE UPDATE ON public.projects
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: scrape_jobs updated_at
CREATE TRIGGER trigger_scrape_jobs_updated_at
BEFORE UPDATE ON public.scrape_jobs
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: scrape_results updated_at
CREATE TRIGGER trigger_scrape_results_updated_at
BEFORE UPDATE ON public.scrape_results
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: api_keys updated_at
CREATE TRIGGER trigger_api_keys_updated_at
BEFORE UPDATE ON public.api_keys
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: schedules updated_at
CREATE TRIGGER trigger_schedules_updated_at
BEFORE UPDATE ON public.schedules
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Trigger: data_storage updated_at
CREATE TRIGGER trigger_data_storage_updated_at
BEFORE UPDATE ON public.data_storage
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

-- Function: Log activity on scrape job changes
CREATE OR REPLACE FUNCTION public.log_scrape_job_activity()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT user_id INTO v_user_id FROM public.projects WHERE id = NEW.project_id;
    
    INSERT INTO public.activity_logs (
        user_id,
        project_id,
        action,
        resource_type,
        resource_id,
        changes
    ) VALUES (
        v_user_id,
        NEW.project_id,
        CASE
            WHEN TG_OP = 'INSERT' THEN 'created'
            WHEN TG_OP = 'UPDATE' THEN 'updated'
            WHEN TG_OP = 'DELETE' THEN 'deleted'
        END,
        'scrape_job',
        CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END,
        CASE
            WHEN TG_OP = 'UPDATE' THEN jsonb_build_object(
                'old_status', OLD.status,
                'new_status', NEW.status,
                'old_name', OLD.name,
                'new_name', NEW.name
            )
            ELSE '{}'::jsonb
        END
    );
    
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Log scrape job activity
CREATE TRIGGER trigger_scrape_job_activity
AFTER INSERT OR UPDATE OR DELETE ON public.scrape_jobs
FOR EACH ROW
EXECUTE FUNCTION public.log_scrape_job_activity();

-- Function: Auto-update job status based on result count
CREATE OR REPLACE FUNCTION public.update_job_status_on_result()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.scrape_jobs
    SET status = 'completed'::public.scrape_status,
        completed_at = CURRENT_TIMESTAMP
    WHERE id = NEW.job_id
      AND status = 'running'::public.scrape_status
      AND completed_at IS NULL;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Update job status on result insert
CREATE TRIGGER trigger_update_job_status
AFTER INSERT ON public.scrape_results
FOR EACH ROW
EXECUTE FUNCTION public.update_job_status_on_result();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrape_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrape_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_storage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USERS RLS POLICIES
-- ============================================================================

-- Users can view their own profile
CREATE POLICY "users_select_own"
ON public.users FOR SELECT
USING (auth.uid() = auth_id);

-- Admins can view all users
CREATE POLICY "users_select_admin"
ON public.users FOR SELECT
USING (
    (SELECT role FROM public.users WHERE auth_id = auth.uid()) = 'admin'::public.user_role
);

-- Users can update their own profile
CREATE POLICY "users_update_own"
ON public.users FOR UPDATE
USING (auth.uid() = auth_id)
WITH CHECK (auth.uid() = auth_id);

-- Admins can update any user
CREATE POLICY "users_update_admin"
ON public.users FOR UPDATE
USING (
    (SELECT role FROM public.users WHERE auth_id = auth.uid()) = 'admin'::public.user_role
)
WITH CHECK (
    (SELECT role FROM public.users WHERE auth_id = auth.uid()) = 'admin'::public.user_role
);

-- ============================================================================
-- PROJECTS RLS POLICIES
-- ============================================================================

-- Users can view their own projects
CREATE POLICY "projects_select_own"
ON public.projects FOR SELECT
USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Anyone can view public projects
CREATE POLICY "projects_select_public"
ON public.projects FOR SELECT
USING (is_public = true);

-- Users can create projects
CREATE POLICY "projects_insert"
ON public.projects FOR INSERT
WITH CHECK (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Users can update their own projects
CREATE POLICY "projects_update_own"
ON public.projects FOR UPDATE
USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()))
WITH CHECK (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- Users can delete their own projects
CREATE POLICY "projects_delete_own"
ON public.projects FOR DELETE
USING (user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

-- ============================================================================
-- SCRAPE JOBS RLS POLICIES
-- ============================================================================

-- Users can view jobs for their projects
CREATE POLICY "scrape_jobs_select"
ON public.scrape_jobs FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can create jobs for their projects
CREATE POLICY "scrape_jobs_insert"
ON public.scrape_jobs FOR INSERT
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can update jobs in their projects
CREATE POLICY "scrape_jobs_update"
ON public.scrape_jobs FOR UPDATE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
)
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can delete jobs in their projects
CREATE POLICY "scrape_jobs_delete"
ON public.scrape_jobs FOR DELETE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- ============================================================================
-- SCRAPE RESULTS RLS POLICIES
-- ============================================================================

-- Users can view results from their projects
CREATE POLICY "scrape_results_select"
ON public.scrape_results FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can insert results for their projects
CREATE POLICY "scrape_results_insert"
ON public.scrape_results FOR INSERT
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can delete results from their projects
CREATE POLICY "scrape_results_delete"
ON public.scrape_results FOR DELETE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- ============================================================================
-- ERROR LOGS RLS POLICIES
-- ============================================================================

-- Users can view error logs for their projects
CREATE POLICY "error_logs_select"
ON public.error_logs FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can insert error logs for their projects
CREATE POLICY "error_logs_insert"
ON public.error_logs FOR INSERT
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- ============================================================================
-- ACTIVITY LOGS RLS POLICIES
-- ============================================================================

-- Users can view their own activity logs
CREATE POLICY "activity_logs_select_own"
ON public.activity_logs FOR SELECT
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Users can view activity logs for their projects
CREATE POLICY "activity_logs_select_project"
ON public.activity_logs FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- System can insert activity logs
CREATE POLICY "activity_logs_insert"
ON public.activity_logs FOR INSERT
WITH CHECK (true);

-- ============================================================================
-- API KEYS RLS POLICIES
-- ============================================================================

-- Users can view their own API keys
CREATE POLICY "api_keys_select"
ON public.api_keys FOR SELECT
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Users can create API keys
CREATE POLICY "api_keys_insert"
ON public.api_keys FOR INSERT
WITH CHECK (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Users can update their own API keys
CREATE POLICY "api_keys_update"
ON public.api_keys FOR UPDATE
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
)
WITH CHECK (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Users can delete their own API keys
CREATE POLICY "api_keys_delete"
ON public.api_keys FOR DELETE
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- ============================================================================
-- SCHEDULES RLS POLICIES
-- ============================================================================

-- Users can view schedules for their projects
CREATE POLICY "schedules_select"
ON public.schedules FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can create schedules for their projects
CREATE POLICY "schedules_insert"
ON public.schedules FOR INSERT
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can update schedules in their projects
CREATE POLICY "schedules_update"
ON public.schedules FOR UPDATE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
)
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can delete schedules in their projects
CREATE POLICY "schedules_delete"
ON public.schedules FOR DELETE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- ============================================================================
-- DATA STORAGE RLS POLICIES
-- ============================================================================

-- Users can view data storage for their projects
CREATE POLICY "data_storage_select"
ON public.data_storage FOR SELECT
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can insert data for their projects
CREATE POLICY "data_storage_insert"
ON public.data_storage FOR INSERT
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can update data in their projects
CREATE POLICY "data_storage_update"
ON public.data_storage FOR UPDATE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
)
WITH CHECK (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- Users can delete data from their projects
CREATE POLICY "data_storage_delete"
ON public.data_storage FOR DELETE
USING (
    project_id IN (
        SELECT id FROM public.projects
        WHERE user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
);

-- ============================================================================
-- NOTIFICATIONS RLS POLICIES
-- ============================================================================

-- Users can view their own notifications
CREATE POLICY "notifications_select"
ON public.notifications FOR SELECT
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- System can insert notifications
CREATE POLICY "notifications_insert"
ON public.notifications FOR INSERT
WITH CHECK (true);

-- Users can update their own notifications
CREATE POLICY "notifications_update"
ON public.notifications FOR UPDATE
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
)
WITH CHECK (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- Users can delete their own notifications
CREATE POLICY "notifications_delete"
ON public.notifications FOR DELETE
USING (
    user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
);

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
