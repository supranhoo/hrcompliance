# Users, roles, permissions and scope administration (migration 0033)

## One source of truth
`role_permission` rows feed both the menu (`my_access()` → UI visibility) and the database (`app.has_permission()` → RLS). No code checks a role *name*. HEAD_HR, PLANT_HR and any custom role get exactly the permissions ticked in the editor.

## Permissions
- `user.admin`: invite users, enable/disable, set scope. `role.admin` (new): create roles, edit role permissions, assign roles. Only SUPER_ADMIN holds `role.admin` by default.
- Splitting them stops "can manage users" from becoming "can make myself SUPER_ADMIN".
- A new permission only comes from a migration (it must map to code); the editor can grant and revoke existing ones.

## Guards (database triggers: apply to the API, the RPCs and the SQL editor)
| Guard | Rule |
|---|---|
| Continuity (SQLSTATE `AD001`) | At least one active, signed-in user must hold `role.admin`. Checked at commit, so a multi-row change that ends valid is allowed. Not bypassable by confirmation. |
| Self-lockout (`AD002`) | Removing your own `user.admin`/`role.admin`, or disabling yourself, is refused unless the RPC is called with `p_confirm_self = true`. The UI shows a confirmation dialog, then repeats the call. |
| Immutability | A role code never changes. The email of a signed-in user cannot change. |
| RLS | Role/permission/assignment writes need `role.admin`; user and scope writes need `user.admin`. Reads: own row, or `user.read`/`user.admin`. |

## RPCs (SECURITY INVOKER, reason mandatory, audited)
`role_save`, `user_invite`, `user_set_roles`, `user_set_status`, `user_set_scope`. Every change writes `audit_log` rows with the reason (table audit triggers, unchanged).

## Screens
Administration → **Users** (invite, status, roles, scope, history) and **Roles & Permissions** (permission matrix grouped by module, change summary, admin-permission warning, history).

## Department scope (owner decision, enforced in the database)
Department is an **additional** dimension only where the protected resource has one. Rule for a user without `scope_all`:
1. `scope_all` bypasses entity, location and department limits.
2. Existing entity/location rule (entity **or** location match) must hold.
3. If the resource has a department (non-null), the user must also hold that department. If it is null, nothing more is required — department is never mandatory.
4. A department alone never grants access (fail closed).

What has a department: an obligation's department is its Compliance Master's `owner_department_id`. Enforced (RLS) on compliance instances, exceptions and their actions, evidence, the applicability matrix and coverage; alert recipients obey the same rule, so nobody is notified about an obligation they cannot open.
Unchanged and globally readable (per their existing permissions): Location, Entity, Compliance Master, rule/reference/legal masters, LOV and configuration. Licences have no department today.
Implementation: new overloads `app.in_scope(entity, location, department)`, `app.scope_ok(...)`, `app.user_scope_ok(user, entity, location, department)`; the 2- and 3-argument forms are untouched, so existing callers behave as before.
**Operational consequence:** once a master has an owning department, restricted users without that department no longer see its obligations. Grant department scope deliberately; the Users → Scope tab says so and shows the effect.

## Known limits
- `generate_alerts` and `resolve_recipients` still route the “owner has no active user” fallback to the role whose code is `HEAD_HR` (a routing default from 0020, not an access decision). Making that fallback configurable is a follow-up.
- System roles keep their name; their permissions are editable.
- Permissions cannot be created or deleted from the UI.
