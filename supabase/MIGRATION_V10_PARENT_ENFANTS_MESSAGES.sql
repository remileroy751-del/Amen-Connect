-- ============================================================================
-- AMEN CONNECT V10 — Parent d'abord + enfants rattachés + lecture des messages
-- ============================================================================
-- À exécuter dans Supabase SQL Editor APRÈS le schéma actuel AMEN CONNECT.
-- Cette migration conserve les parents, élèves, notes, conversations et
-- communiqués existants.
--
-- Changements :
-- 1) La Direction crée d'abord un parent : un code d'accès est généré.
-- 2) Les enfants sont ensuite créés en les rattachant explicitement à ce parent.
-- 3) Le formulaire « élève + parent » n'est plus nécessaire.
-- 4) Suppression complète de l'ancien système « Bien reçu / accusé de réception ».
-- 5) Nouveau suivi « message lu / non lu » par parent + enfant.
-- 6) Une fonction permet de marquer tous les messages visibles d'un enfant comme lus.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Ancien système d'accusé de réception : suppression
-- ---------------------------------------------------------------------------

drop function if exists public.acknowledge_announcement(text, uuid, uuid);
drop function if exists public.student_announcements(text, uuid);
drop table if exists public.announcement_receipts cascade;

-- ---------------------------------------------------------------------------
-- 2. Nouveau système de lecture des messages
-- ---------------------------------------------------------------------------

create table if not exists public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  parent_id uuid not null references public.parents(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, parent_id, student_id)
);

create index if not exists idx_announcement_reads_parent_student
  on public.announcement_reads(parent_id, student_id, read_at desc);

create index if not exists idx_announcement_reads_announcement
  on public.announcement_reads(announcement_id);

alter table public.announcement_reads enable row level security;

revoke all on public.announcement_reads from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Ajouter un enfant à un parent existant
-- ---------------------------------------------------------------------------

-- L'ancien RPC qui créait simultanément élève + parent n'est plus utilisé.
drop function if exists public.admin_create_student(text, uuid, text, text);

create or replace function public.admin_create_student_for_parent(
  p_student_full_name text,
  p_class_id uuid,
  p_parent_id uuid,
  p_relationship text default 'Parent'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_relationship text := coalesce(nullif(trim(p_relationship), ''), 'Parent');
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_student_full_name), '') is null then
    raise exception 'Nom de l''élève obligatoire.';
  end if;

  if p_parent_id is null or not exists (
    select 1 from public.parents where id = p_parent_id
  ) then
    raise exception 'Parent introuvable.';
  end if;

  if p_class_id is null or not exists (
    select 1 from public.classes where id = p_class_id
  ) then
    raise exception 'Classe introuvable.';
  end if;

  insert into public.students(full_name, class_id)
  values (trim(p_student_full_name), p_class_id)
  returning id into v_student_id;

  insert into public.student_parents(student_id, parent_id, relationship)
  values (v_student_id, p_parent_id, v_relationship);

  return jsonb_build_object(
    'success', true,
    'student_id', v_student_id,
    'parent_id', p_parent_id,
    'relationship', v_relationship
  );
end;
$$;

grant execute on function public.admin_create_student_for_parent(text, uuid, uuid, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Liste des messages Direction d'un enfant avec statut lu/non lu
-- ---------------------------------------------------------------------------

create or replace function public.student_announcements(
  p_code text,
  p_student_id uuid
)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  target_type text,
  created_at timestamptz,
  is_read boolean
)
language sql
security definer
set search_path = public
as $$
  select
    a.id,
    a.title,
    a.body,
    a.importance,
    a.target_type,
    a.created_at,
    exists (
      select 1
      from public.announcement_reads ar
      where ar.announcement_id = a.id
        and ar.parent_id = p.id
        and ar.student_id = p_student_id
    ) as is_read
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id
   and sp.student_id = p_student_id
  join public.students s
    on s.id = sp.student_id
  join public.announcements a
    on (
      a.target_type in ('all', 'all_parents')
      or (a.target_type in ('class', 'class_parents') and a.class_id = s.class_id)
      or (a.target_type = 'student' and a.student_id = s.id)
      or (a.target_type = 'parent' and a.parent_id = p.id)
    )
  where p.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

grant execute on function public.student_announcements(text, uuid)
to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Marquer tous les messages visibles d'un enfant comme lus
-- ---------------------------------------------------------------------------

create or replace function public.mark_announcements_read(
  p_code text,
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
  v_count integer := 0;
begin
  select p.id
    into v_parent_id
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id
   and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then
    raise exception 'Parent ou élève non autorisé.';
  end if;

  insert into public.announcement_reads(
    announcement_id, parent_id, student_id, read_at
  )
  select
    a.id, v_parent_id, p_student_id, now()
  from public.announcements a
  join public.students s on s.id = p_student_id
  where (
    a.target_type in ('all', 'all_parents')
    or (a.target_type in ('class', 'class_parents') and a.class_id = s.class_id)
    or (a.target_type = 'student' and a.student_id = s.id)
    or (a.target_type = 'parent' and a.parent_id = v_parent_id)
  )
  on conflict (announcement_id, parent_id, student_id)
  do update set read_at = excluded.read_at;

  get diagnostics v_count = row_count;

  return jsonb_build_object(
    'success', true,
    'read_count', v_count
  );
end;
$$;

grant execute on function public.mark_announcements_read(text, uuid)
to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Suppression Direction des communiqués reste sécurisée
-- ---------------------------------------------------------------------------
-- admin_delete_announcements() continue de fonctionner. La suppression d'un
-- communiqué supprime automatiquement son statut de lecture grâce à ON DELETE
-- CASCADE sur announcement_reads.

-- ---------------------------------------------------------------------------
-- FIN V10
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 7. Rattacher les anciens élèves qui auraient été créés sans parent
-- ---------------------------------------------------------------------------
-- Utile pour les données déjà présentes avant V10. Cela permet à la Direction
-- de corriger les anciens élèves orphelins sans recréer leur fiche.

create or replace function public.admin_link_student_to_parent(
  p_student_id uuid,
  p_parent_id uuid,
  p_relationship text default 'Parent'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_relationship text := coalesce(nullif(trim(p_relationship), ''), 'Parent');
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if not exists (select 1 from public.students where id = p_student_id) then
    raise exception 'Élève introuvable.';
  end if;

  if not exists (select 1 from public.parents where id = p_parent_id) then
    raise exception 'Parent introuvable.';
  end if;

  insert into public.student_parents(student_id, parent_id, relationship)
  values (p_student_id, p_parent_id, v_relationship)
  on conflict (student_id, parent_id)
  do update set relationship = excluded.relationship;

  return jsonb_build_object(
    'success', true,
    'student_id', p_student_id,
    'parent_id', p_parent_id
  );
end;
$$;

grant execute on function public.admin_link_student_to_parent(uuid, uuid, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- FIN V10
-- ---------------------------------------------------------------------------
