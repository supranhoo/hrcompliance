import { NotConfiguredError, type DocumentStorageService, type MailService, type ServiceStatus, type SpreadsheetImportService } from './contracts'

const NC: ServiceStatus = { state: 'NOT_CONFIGURED', detail: 'No adapter attached in this environment' }
const fail = (n: string): never => { throw new NotConfiguredError(n) }

export const notConfiguredStorage: DocumentStorageService = {
  name: 'google-drive', status: async () => NC,
  upload: async () => fail('DocumentStorageService'), getDownloadUrl: async () => fail('DocumentStorageService'), remove: async () => fail('DocumentStorageService'),
}
export const notConfiguredMail: MailService = {
  name: 'gmail', status: async () => NC,
  createDraft: async () => fail('MailService'), send: async () => fail('MailService'),
}
export const notConfiguredImport: SpreadsheetImportService = {
  name: 'spreadsheet-import', status: async () => NC, preview: async () => fail('SpreadsheetImportService'),
}

export type Services = { storage: DocumentStorageService; mail: MailService; spreadsheetImport: SpreadsheetImportService }
let current: Services = { storage: notConfiguredStorage, mail: notConfiguredMail, spreadsheetImport: notConfiguredImport }
/** Attach real adapters at app start (e.g. Edge-Function-backed Drive/Gmail). Modules call getServices(), never an adapter directly. */
export const configureServices = (s: Partial<Services>) => { current = { ...current, ...s } }
export const getServices = () => current
export * from './contracts'
