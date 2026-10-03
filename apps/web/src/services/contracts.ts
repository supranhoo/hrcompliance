/**
 * External-service contracts. Business modules depend ONLY on these interfaces; adapters (Google Drive, Gmail, Excel import)
 * are attached later without touching module code. Until configured, the registry returns NOT_CONFIGURED adapters.
 */
export type ServiceState = 'NOT_CONFIGURED' | 'CONFIGURED' | 'ERROR'
export interface ServiceStatus { state: ServiceState; detail?: string }

export type StoredFile = { storageId: string; name: string; mimeType: string; sizeBytes: number; checksum?: string; url?: string }
export interface DocumentStorageService {
  readonly name: string
  status(): Promise<ServiceStatus>
  upload(input: { file: File; folderHint: string; metadata?: Record<string, string> }): Promise<StoredFile>
  getDownloadUrl(storageId: string): Promise<string>
  remove(storageId: string): Promise<void>
}

export type MailMessage = { from?: string; to: string[]; cc?: string[]; bcc?: string[]; subject: string; html: string; attachments?: StoredFile[]; relatedModule?: string; relatedRecordId?: string }
export interface MailService {
  readonly name: string
  status(): Promise<ServiceStatus>
  /** Creates a draft only. Sending formal communications requires an explicit human action in the UI (req. 54). */
  createDraft(m: MailMessage): Promise<{ draftId: string }>
  /** Must be called only from a user-initiated, reviewed send action. */
  send(draftId: string): Promise<{ messageId: string }>
}

export type ImportPreview = { sheets: Array<{ name: string; headers: string[]; sampleRows: unknown[][]; rowCount: number }> }
export interface SpreadsheetImportService {
  readonly name: string
  status(): Promise<ServiceStatus>
  /** Parses a user-selected file into a preview. Never writes business data; the Import Centre validates and commits. */
  preview(file: File): Promise<ImportPreview>
}

export class NotConfiguredError extends Error {
  constructor(public readonly service: string) { super(`${service} is not configured`); this.name = 'NotConfiguredError' }
}
