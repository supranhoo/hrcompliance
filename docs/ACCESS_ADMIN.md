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

## Known limits
- Department scope exists in `user_scope` but `app.in_scope` does not enforce it, so the screens manage entity and location scope only. Owner decision needed before enforcing department scope.
- System roles keep their name; their permissions are editable.
- Permissions cannot be created or deleted from the UI.
