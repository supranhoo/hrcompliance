import { useParams } from 'react-router-dom'
import { AdminRegister } from './AdminRegister'
import { complianceMasterSpec, REFERENCE_MASTERS } from './masters'
import { NotFoundPage } from '../pages/Pages'
export { RuleVersionsPage } from './ruleVersions'

export const ComplianceMasterPage = () => <AdminRegister spec={complianceMasterSpec} />
export function ReferenceMasterPage() {
  const { kind } = useParams(); const spec = kind ? REFERENCE_MASTERS[kind] : undefined
  return spec ? <AdminRegister key={kind} spec={spec} /> : <NotFoundPage />
}
export { ApplicabilityPage, CoveragePage } from './applicability'
