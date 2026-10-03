import { afterEach, describe, expect, it } from 'vitest'
import { configureServices, getServices, NotConfiguredError, notConfiguredMail, notConfiguredStorage } from './index'

describe('external service abstractions', () => {
  afterEach(() => configureServices({ storage: notConfiguredStorage, mail: notConfiguredMail }))
  it('default adapters report NOT_CONFIGURED without throwing', async () => {
    const s = getServices()
    expect((await s.storage.status()).state).toBe('NOT_CONFIGURED')
    expect((await s.mail.status()).state).toBe('NOT_CONFIGURED')
    expect((await s.spreadsheetImport.status()).state).toBe('NOT_CONFIGURED')
  })
  it('operations on unconfigured adapters fail with a typed error', async () => {
    await expect(getServices().storage.upload({ file: new File(['x'], 'a.pdf'), folderHint: 'x' })).rejects.toBeInstanceOf(NotConfiguredError)
    await expect(getServices().mail.send('d1')).rejects.toBeInstanceOf(NotConfiguredError)
  })
  it('adapters can be attached without changing callers', async () => {
    configureServices({ mail: { name: 'fake', status: async () => ({ state: 'CONFIGURED' }), createDraft: async () => ({ draftId: 'd' }), send: async () => ({ messageId: 'm' }) } })
    expect((await getServices().mail.status()).state).toBe('CONFIGURED')
    expect(await getServices().mail.createDraft({ to: ['a@b.c'], subject: 's', html: '' })).toEqual({ draftId: 'd' })
  })
})
