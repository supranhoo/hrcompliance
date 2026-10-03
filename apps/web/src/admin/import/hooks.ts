import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type { TemplateDef } from './importFile'

export type TemplateRow = { code: string; name: string; description: string | null; write_permission: string; is_active: boolean }
export function useTemplates() {
  return useQuery({ queryKey: ['import-templates'], enabled: !!supabase, queryFn: async (): Promise<TemplateRow[]> => {
    const { data, error } = await supabase!.from('import_template').select('code,name,description,write_permission,is_active').eq('is_active', true).order('name'); if (error) throw error; return (data ?? []) as TemplateRow[] } })
}
/** The template (columns, key, limits) is read from the database every time: the screen never carries its own copy. */
export function useTemplateDef(code: string | undefined) {
  return useQuery({ queryKey: ['import-template-def', code], enabled: !!code && !!supabase, staleTime: 60_000, queryFn: async (): Promise<TemplateDef> => {
    const { data, error } = await supabase!.rpc('import_template_columns', { p_template: code }); if (error) throw error; return data as TemplateDef } })
}
