/* LyxPanel v4.6 - Extended JS (safe rebuild)
   Notes:
   - Rebuilt to recover from syntax corruption.
   - Keeps compatibility with existing app.js globals.
   - Avoids emoji text; uses icon markup where needed.
*/

(function () {
  'use strict';

  function esc(value) {
    if (value === null || value === undefined) return '';
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function toInt(value, fallback) {
    const n = parseInt(value, 10);
    return Number.isFinite(n) ? n : fallback;
  }

  function getSelectedPlayer() {
    try {
      if (typeof selectedPlayer !== 'undefined' && selectedPlayer && selectedPlayer.id) {
        return selectedPlayer;
      }
    } catch (_) {}
    return null;
  }

  function notify(type, message) {
    if (typeof window.showToast === 'function') {
      window.showToast(type || 'info', message || '');
    }
  }

  function sanitizeUiText(value) {
    if (value === null || value === undefined) return '';
    return String(value)
      .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, '')
      .replace(/[\u00C2\u00C3\u00E2\u00EF\u00B8\u008F\u00F0\u0178]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  if (typeof window.showToast === 'function' && !window.showToast.__lyxPatched) {
    const originalShowToast = window.showToast;
    window.showToast = function patchedShowToast(type, message) {
      return originalShowToast(type, sanitizeUiText(message));
    };
    window.showToast.__lyxPatched = true;
  }

  // Unify toast API (some legacy code uses Toast.* while newer code uses showToast).
  window.Toast = {
    __lyxUnified: true,
    show(type, title, message) {
      const parts = [];
      if (title) parts.push(sanitizeUiText(title));
      if (message) parts.push(sanitizeUiText(message));
      const text = parts.join(': ') || 'Notificacion';
      if (typeof window.showToast === 'function') {
        window.showToast(type || 'info', text);
      }
    },
    success(title, message) { this.show('success', title, message); },
    error(title, message) { this.show('error', title, message); },
    warning(title, message) { this.show('warning', title, message); },
    info(title, message) { this.show('info', title, message); }
  };

  if (typeof window.postNuiJson !== 'function') {
    window.postNuiJson = function postNuiJson(route, payload) {
      const data = payload || {};
      const sec = (typeof NUISecurity !== 'undefined')
        ? NUISecurity
        : window.NUISecurity;
      if (sec && typeof sec.canSendRequest === 'function') {
        if (!sec.canSendRequest()) {
          return Promise.resolve({ success: false, error: 'rate_limited' });
        }
      }

      const resource = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'lyx-panel';

      return fetch(`https://${resource}/${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
      })
        .then((r) => r.json().catch(() => ({})))
        .catch(() => ({ success: false, error: 'network_error' }));
    };
  }

  // ---------------------------------------------------------------------------
  // Tickets (support) - in-game workflow for staff
  // ---------------------------------------------------------------------------

  const TicketsState = {
    offset: 0,
    limit: 50,
    total: 0,
    rows: [],
    selectedId: null,
  };

  function getEl(id) {
    return document.getElementById(id);
  }

  function readTicketsFilters() {
    const status = (getEl('ticketStatus') && getEl('ticketStatus').value) || '';
    const search = sanitizeUiText((getEl('ticketSearch') && getEl('ticketSearch').value) || '');
    const limit = toInt((getEl('ticketLimit') && getEl('ticketLimit').value) || '50', 50);
    TicketsState.limit = Math.min(200, Math.max(10, limit));
    return { status, search, limit: TicketsState.limit, offset: TicketsState.offset };
  }

  function fmtTicketStatus(s) {
    const v = String(s || '').toLowerCase();
    if (v === 'open') return '<span class="badge badge-danger">abierto</span>';
    if (v === 'answered') return '<span class="badge badge-info">respondido</span>';
    if (v === 'closed') return '<span class="badge badge-success">cerrado</span>';
    return esc(v || 'n/a');
  }

  function renderTicketsTable() {
    const body = getEl('ticketsTableBody');
    if (!body) return;

    const rows = TicketsState.rows || [];
    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="6" style="color: var(--text-secondary);">Sin tickets</td></tr>';
      return;
    }

    body.innerHTML = rows.map((t) => {
      const id = Number(t.id || 0);
      const selected = TicketsState.selectedId === id ? ' selected' : '';
      const assigned = sanitizeUiText(t.assigned_to_name || '');
      const created = sanitizeUiText(t.created_at || '');
      return (
        `<tr class="ticket-row${selected}" data-ticket-id="${id}">` +
          `<td>#${id}</td>` +
          `<td>${esc(sanitizeUiText(t.player_name || ''))}</td>` +
          `<td>${esc(sanitizeUiText(t.subject || ''))}</td>` +
          `<td>${fmtTicketStatus(t.status)}</td>` +
          `<td>${esc(assigned || '-')}</td>` +
          `<td>${esc(created || '')}</td>` +
        `</tr>`
      );
    }).join('');

    // Click handlers
    body.querySelectorAll('tr.ticket-row').forEach((tr) => {
      tr.addEventListener('click', () => {
        const id = toInt(tr.getAttribute('data-ticket-id'), 0);
        if (!id) return;
        ticketSelect(id);
      });
    });
  }

  function updateTicketsPageInfo() {
    const el = getEl('ticketPageInfo');
    if (!el) return;
    const total = TicketsState.total || 0;
    const start = total === 0 ? 0 : TicketsState.offset + 1;
    const end = Math.min(total, TicketsState.offset + (TicketsState.limit || 0));
    el.textContent = `${start}-${end} / ${total}`;
  }

  function renderTicketDetail() {
    const titleEl = getEl('ticketDetailTitle');
    const subEl = getEl('ticketDetailSub');
    const msgEl = getEl('ticketDetailMessage');
    const respEl = getEl('ticketDetailResponse');
    if (!titleEl || !subEl || !msgEl || !respEl) return;

    const id = TicketsState.selectedId;
    const t = (TicketsState.rows || []).find((r) => Number(r.id || 0) === Number(id || 0));
    if (!t) {
      titleEl.textContent = 'Selecciona un ticket';
      subEl.textContent = '';
      msgEl.textContent = '-';
      respEl.textContent = '-';
      return;
    }

    const player = sanitizeUiText(t.player_name || '');
    const subj = sanitizeUiText(t.subject || '');
    const status = String(t.status || '').toLowerCase();
    const assigned = sanitizeUiText(t.assigned_to_name || '');

    titleEl.textContent = `#${t.id} | ${subj || 'Ticket'}`;
    subEl.textContent = `${player || 'Jugador'} | ${status || 'n/a'} | asignado: ${assigned || '-'}`;
    msgEl.textContent = sanitizeUiText(t.message || '');
    respEl.textContent = sanitizeUiText(t.admin_response || '');
  }

  async function loadTickets(resetOffset) {
    try {
      if (resetOffset === true) TicketsState.offset = 0;
      const filters = readTicketsFilters();
      const resp = await window.postNuiJson('getTickets', filters);
      if (!resp || resp.success !== true) {
        notify('error', 'No se pudo cargar tickets');
        TicketsState.rows = [];
        TicketsState.total = 0;
        renderTicketsTable();
        updateTicketsPageInfo();
        renderTicketDetail();
        return;
      }

      TicketsState.rows = Array.isArray(resp.rows) ? resp.rows : [];
      TicketsState.total = toInt(resp.total, TicketsState.rows.length || 0);
      // Keep selected in sync if it no longer exists.
      if (TicketsState.selectedId) {
        const exists = TicketsState.rows.some((r) => Number(r.id || 0) === Number(TicketsState.selectedId));
        if (!exists) TicketsState.selectedId = null;
      }

      renderTicketsTable();
      updateTicketsPageInfo();
      renderTicketDetail();
    } catch (e) {
      notify('error', 'Error cargando tickets');
      // eslint-disable-next-line no-console
      console.error(e);
    }
  }

  function ticketSelect(id) {
    TicketsState.selectedId = Number(id || 0) || null;
    renderTicketsTable();
    renderTicketDetail();
  }

  function ticketsPrev() {
    TicketsState.offset = Math.max(0, TicketsState.offset - (TicketsState.limit || 50));
    loadTickets(false);
  }

  function ticketsNext() {
    const next = TicketsState.offset + (TicketsState.limit || 50);
    if (next >= (TicketsState.total || 0)) return;
    TicketsState.offset = next;
    loadTickets(false);
  }

  function ticketsReset() {
    const s = getEl('ticketStatus');
    const q = getEl('ticketSearch');
    const l = getEl('ticketLimit');
    if (s) s.value = '';
    if (q) q.value = '';
    if (l) l.value = '50';
    TicketsState.offset = 0;
    TicketsState.selectedId = null;
    loadTickets(true);
  }

  function canManageTickets() {
    try {
      if (typeof window.perm === 'function') {
        return window.perm('canManageTickets') || window.perm('canUseTickets');
      }
    } catch (_) {}
    return true;
  }

  function ticketAssignMe() {
    if (!canManageTickets()) return notify('error', 'Sin permisos');
    if (!TicketsState.selectedId) return notify('warning', 'Selecciona un ticket');
    window.postNuiJson('action', { action: 'ticketAssign', ticketId: TicketsState.selectedId }).then(() => {
      setTimeout(() => loadTickets(false), 600);
    });
  }

  function ticketReply() {
    if (!canManageTickets()) return notify('error', 'Sin permisos');
    if (!TicketsState.selectedId) return notify('warning', 'Selecciona un ticket');
    const ta = getEl('ticketReplyText');
    const msg = sanitizeUiText(ta ? ta.value : '');
    if (!msg) return notify('warning', 'Respuesta vacia');
    if (ta) ta.value = '';
    window.postNuiJson('action', { action: 'ticketReply', ticketId: TicketsState.selectedId, message: msg }).then(() => {
      setTimeout(() => loadTickets(false), 650);
    });
  }

  function ticketClose() {
    if (!canManageTickets()) return notify('error', 'Sin permisos');
    if (!TicketsState.selectedId) return notify('warning', 'Selecciona un ticket');
    const input = getEl('ticketCloseReason');
    const reason = sanitizeUiText(input ? input.value : '');
    if (input) input.value = '';
    window.postNuiJson('action', { action: 'ticketClose', ticketId: TicketsState.selectedId, reason }).then(() => {
      setTimeout(() => loadTickets(false), 650);
    });
  }

  function ticketReopen() {
    if (!canManageTickets()) return notify('error', 'Sin permisos');
    if (!TicketsState.selectedId) return notify('warning', 'Selecciona un ticket');
    window.postNuiJson('action', { action: 'ticketReopen', ticketId: TicketsState.selectedId }).then(() => {
      setTimeout(() => loadTickets(false), 650);
    });
  }

  window.loadTickets = loadTickets;
  window.ticketsPrev = ticketsPrev;
  window.ticketsNext = ticketsNext;
  window.ticketsReset = ticketsReset;
  window.ticketAssignMe = ticketAssignMe;
  window.ticketReply = ticketReply;
  window.ticketClose = ticketClose;
  window.ticketReopen = ticketReopen;


  if (typeof window.sendNUI !== 'function') {
    window.sendNUI = function sendNUI(payload, cb) {
      return window.postNuiJson('action', payload || {}).then((resp) => {
        if (typeof cb === 'function') cb(resp || {});
        return resp || {};
      });
    };
  }

  function nuiJson(route, payload) {
    const data = payload || {};
    if (typeof window.postNuiJson === 'function') {
      return window.postNuiJson(route, data);
    }

    const resource = (typeof GetParentResourceName === 'function')
      ? GetParentResourceName()
      : 'lyx-panel';

    return fetch(`https://${resource}/${route}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data)
    }).then((r) => r.json()).catch(() => ({}));
  }

  function openInput(title, html) {
    if (typeof window.openInputModal === 'function') {
      window.openInputModal(title, html);
      return true;
    }
    return false;
  }

  function closeInput() {
    if (typeof window.closeInputModal === 'function') {
      window.closeInputModal();
    }
  }

  function getValue(id) {
    const el = document.getElementById(id);
    return el ? String(el.value || '') : '';
  }

  const PermissionEditor = {
    roles: [],
    permissionKeys: [],
    roleData: null,
    individualData: null
  };

  function permissionErrorText(resp, fallback) {
    if (resp && typeof resp.error === 'string' && resp.error !== '') {
      return `Error: ${resp.error}`;
    }
    return fallback || 'Operacion fallida';
  }

  function boolLabel(value) {
    return value === true ? 'ALLOW' : 'DENY';
  }

  function boolBadge(value) {
    return value === true
      ? '<span class="badge badge-success">ALLOW</span>'
      : '<span class="badge badge-danger">DENY</span>';
  }

  function refreshPermissionSelects() {
    const roleSelect = document.getElementById('permRoleSelect');
    const keySelect = document.getElementById('permIndividualKey');
    const accessGroup = document.getElementById('accessGroup');

    if (roleSelect) {
      roleSelect.innerHTML = PermissionEditor.roles
        .map((r) => `<option value="${esc(r)}">${esc(r)}</option>`)
        .join('');
    }

    if (keySelect) {
      keySelect.innerHTML = PermissionEditor.permissionKeys
        .map((k) => `<option value="${esc(k)}">${esc(k)}</option>`)
        .join('');
    }

    if (accessGroup) {
      accessGroup.innerHTML = PermissionEditor.roles
        .map((r) => `<option value="${esc(r)}">${esc(r)}</option>`)
        .join('');
    }
  }

  function renderRolePermissions() {
    const wrap = document.getElementById('permRoleTable');
    if (!wrap) return;

    const data = PermissionEditor.roleData;
    if (!data) {
      wrap.innerHTML = '<p>Selecciona un rol y pulsa "Ver rol".</p>';
      return;
    }

    const query = getValue('permKeySearch').trim().toLowerCase();
    const keys = PermissionEditor.permissionKeys.length > 0
      ? PermissionEditor.permissionKeys
      : Object.keys(data.effective || {});

    const rows = keys
      .filter((k) => !query || k.toLowerCase().includes(query))
      .map((perm) => {
        const permToken = encodeURIComponent(perm);
        const base = data.base && Object.prototype.hasOwnProperty.call(data.base, perm) ? data.base[perm] : null;
        const override = data.override && Object.prototype.hasOwnProperty.call(data.override, perm) ? data.override[perm] : null;
        const effective = data.effective && Object.prototype.hasOwnProperty.call(data.effective, perm) ? data.effective[perm] : false;
        return `
          <tr>
            <td><code>${esc(perm)}</code></td>
            <td>${base === null ? '<span class="badge badge-secondary">N/A</span>' : boolBadge(base)}</td>
            <td>${override === null ? '<span class="badge badge-secondary">DEFAULT</span>' : boolBadge(override)}</td>
            <td>${boolBadge(effective)}</td>
            <td style="display:flex; gap:6px;">
              <button class="btn btn-primary btn-sm" onclick="permissionsSetRole(decodeURIComponent('${permToken}'), true)">ALLOW</button>
              <button class="btn btn-danger btn-sm" onclick="permissionsSetRole(decodeURIComponent('${permToken}'), false)">DENY</button>
            </td>
          </tr>
        `;
      })
      .join('');

    wrap.innerHTML = rows
      ? `
        <table class="data-table">
          <thead>
            <tr>
              <th>Permiso</th>
              <th>Base</th>
              <th>Override</th>
              <th>Efectivo</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      `
      : '<p>No se encontraron permisos para ese filtro.</p>';
  }

  function renderIndividualPermissions() {
    const wrap = document.getElementById('permIndividualTable');
    if (!wrap) return;

    const data = PermissionEditor.individualData;
    if (!data || !data.identifier) {
      wrap.innerHTML = '<p>Ingresa un identifier y pulsa "Ver".</p>';
      return;
    }

    const overrides = data.overrides || {};
    const keys = Object.keys(overrides);
    if (keys.length === 0) {
      wrap.innerHTML = '<p>Sin overrides individuales para este identifier.</p>';
      return;
    }

    const rows = keys
      .sort()
      .map((k) => `
        <tr>
          <td><code>${esc(k)}</code></td>
          <td>${boolBadge(overrides[k] === true)}</td>
        </tr>
      `)
      .join('');

    wrap.innerHTML = `
      <table class="data-table">
        <thead>
          <tr>
            <th>Permiso</th>
            <th>Valor</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  }

  function renderAccessEntries(rows) {
    const wrap = document.getElementById('accessTable');
    if (!wrap) return;

    const list = Array.isArray(rows) ? rows : [];
    if (list.length === 0) {
      wrap.innerHTML = '<p>Sin entries de acceso.</p>';
      return;
    }

    const tableRows = list
      .map((r) => {
        const id = r.identifier || '';
        const idToken = encodeURIComponent(id);
        return `
        <tr>
          <td><code>${esc(id)}</code></td>
          <td>${esc(r.group_name || '')}</td>
          <td>${esc(r.note || '')}</td>
          <td>${esc(r.updated_at || r.created_at || '')}</td>
          <td>
            <button class="btn btn-danger btn-sm" onclick="accessRemove(decodeURIComponent('${idToken}'))">Quitar</button>
          </td>
        </tr>
      `;
      })
      .join('');

    wrap.innerHTML = `
      <table class="data-table">
        <thead>
          <tr>
            <th>Identifier</th>
            <th>Grupo</th>
            <th>Nota</th>
            <th>Actualizado</th>
            <th>Accion</th>
          </tr>
        </thead>
        <tbody>${tableRows}</tbody>
      </table>
    `;
  }

  function permissionsLoad() {
    return nuiJson('getPermissionEditorData', {}).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo cargar editor de permisos'));
        return;
      }

      PermissionEditor.roles = Array.isArray(resp.roles) ? resp.roles : [];
      PermissionEditor.permissionKeys = Array.isArray(resp.permissionKeys) ? resp.permissionKeys : [];

      refreshPermissionSelects();
      renderRolePermissions();
      renderIndividualPermissions();

      const roleSelect = document.getElementById('permRoleSelect');
      if (roleSelect && roleSelect.value) {
        permissionsLoadRole();
      }

      accessReload();
    });
  }

  function permissionsLoadRole() {
    const role = getValue('permRoleSelect').trim();
    if (!role) {
      notify('warning', 'Selecciona un rol');
      return;
    }

    nuiJson('getRolePermissions', { role }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo cargar permisos del rol'));
        return;
      }
      PermissionEditor.roleData = resp;
      renderRolePermissions();
    });
  }

  function permissionsSetRole(permission, value) {
    const role = getValue('permRoleSelect').trim();
    if (!role || !permission) {
      notify('error', 'Rol o permiso invalido');
      return;
    }

    nuiJson('setRolePermission', {
      role,
      permission,
      value: value === true
    }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo actualizar el permiso'));
        return;
      }
      notify('success', `Permiso ${permission} actualizado a ${boolLabel(value === true)}`);
      permissionsLoadRole();
    });
  }

  function permissionsResetRole() {
    const role = getValue('permRoleSelect').trim();
    if (!role) {
      notify('warning', 'Selecciona un rol');
      return;
    }

    const run = () => {
      nuiJson('resetRoleOverride', { role }).then((resp) => {
        if (!resp || resp.success !== true) {
          notify('error', permissionErrorText(resp, 'No se pudo resetear el rol'));
          return;
        }
        notify('success', `Override del rol ${role} reseteado`);
        permissionsLoadRole();
      });
    };

    if (typeof window.showConfirm === 'function') {
      window.showConfirm('Reset override', `Resetear override del rol ${role}?`, run);
    } else if (window.confirm(`Resetear override del rol ${role}?`)) {
      run();
    }
  }

  function permissionsLoadIndividual() {
    const identifier = getValue('permIdentifier').trim();
    if (!identifier) {
      notify('warning', 'Ingresa un identifier');
      return;
    }

    nuiJson('getIndividualPermissions', { identifier }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo cargar permisos individuales'));
        return;
      }
      PermissionEditor.individualData = {
        identifier: resp.identifier || identifier,
        overrides: resp.overrides || {}
      };
      renderIndividualPermissions();
    });
  }

  function permissionsSetIndividual() {
    const identifier = getValue('permIdentifier').trim();
    const permission = getValue('permIndividualKey').trim();
    const rawValue = getValue('permIndividualValue').trim().toLowerCase();
    const value = rawValue === 'true';

    if (!identifier || !permission) {
      notify('warning', 'Identifier y permiso son obligatorios');
      return;
    }

    nuiJson('setIndividualPermission', {
      identifier,
      permission,
      value
    }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo guardar permiso individual'));
        return;
      }
      notify('success', `Override individual guardado: ${permission}=${boolLabel(value)}`);
      permissionsLoadIndividual();
    });
  }

  function permissionsResetIndividual() {
    const identifier = getValue('permIdentifier').trim();
    const permission = getValue('permIndividualKey').trim();

    if (!identifier || !permission) {
      notify('warning', 'Identifier y permiso son obligatorios');
      return;
    }

    nuiJson('resetIndividualPermission', {
      identifier,
      permission
    }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo resetear permiso individual'));
        return;
      }
      notify('success', `Override individual eliminado: ${permission}`);
      permissionsLoadIndividual();
    });
  }

  function accessReload() {
    nuiJson('listAccessEntries', {}).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo cargar access list'));
        return;
      }
      renderAccessEntries(resp.rows || []);
    });
  }

  function accessGrant() {
    const identifier = getValue('accessIdentifier').trim();
    const group = getValue('accessGroup').trim();
    const note = getValue('accessNote').trim();

    if (!identifier || !group) {
      notify('warning', 'Identifier y grupo son obligatorios');
      return;
    }

    nuiJson('setAccessEntry', { identifier, group, note }).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo guardar access entry'));
        return;
      }
      notify('success', 'Access entry guardado');
      accessReload();
    });
  }

  function accessRemove(identifier) {
    const clean = (identifier || '').trim();
    if (!clean) return;

    const run = () => {
      nuiJson('removeAccessEntry', { identifier: clean }).then((resp) => {
        if (!resp || resp.success !== true) {
          notify('error', permissionErrorText(resp, 'No se pudo eliminar access entry'));
          return;
        }
        notify('success', 'Access entry eliminado');
        accessReload();
      });
    };

    if (typeof window.showConfirm === 'function') {
      window.showConfirm('Eliminar acceso', `Quitar acceso de ${clean}?`, run);
    } else if (window.confirm(`Quitar acceso de ${clean}?`)) {
      run();
    }
  }

  function bindPermissionEditorUi() {
    const search = document.getElementById('permKeySearch');
    if (search && !search.dataset.lyxBound) {
      search.dataset.lyxBound = '1';
      search.addEventListener('input', renderRolePermissions);
    }

    document.addEventListener('click', (evt) => {
      const nav = evt.target.closest('.nav-item[data-page="permissions"]');
      if (!nav) return;
      setTimeout(() => {
        if (typeof window.permissionsLoad === 'function') {
          window.permissionsLoad();
        }
      }, 0);
    });
  }

  function openOfflineBan() {
    openInput('Ban Offline', [
      '<div class="form-group">',
      '<label>Identifier</label>',
      '<input type="text" id="banIdentifier" placeholder="license:xxxx" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Nombre (opcional)</label>',
      '<input type="text" id="banPlayerName" placeholder="Nombre del jugador" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Razon</label>',
      '<input type="text" id="banReason" placeholder="Motivo del ban" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Duracion</label>',
      '<select id="banDuration" class="input-full">',
      '<option value="24">24 Horas</option>',
      '<option value="168">1 Semana</option>',
      '<option value="720">1 Mes</option>',
      '<option value="permanent">Permanente</option>',
      '</select>',
      '</div>',
      '<button class="btn btn-danger btn-full" onclick="submitOfflineBan()">',
      '<i class="fas fa-ban"></i> Aplicar Ban</button>'
    ].join(''));
  }

  function submitOfflineBan() {
    const identifier = getValue('banIdentifier').trim();
    const reason = getValue('banReason').trim();

    if (!identifier || !reason) {
      notify('error', 'Identifier y razon son obligatorios');
      return;
    }

    nuiJson('banOffline', {
      identifier,
      playerName: getValue('banPlayerName').trim(),
      reason,
      duration: getValue('banDuration')
    });

    closeInput();
  }

  function openIPBan() {
    openInput('Ban por Rango IP', [
      '<div class="form-group">',
      '<label>Rango IP</label>',
      '<input type="text" id="ipRange" placeholder="192.168.1.*" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Razon</label>',
      '<input type="text" id="ipBanReason" placeholder="Motivo" class="input-full">',
      '</div>',
      '<button class="btn btn-danger btn-full" onclick="submitIPBan()">',
      '<i class="fas fa-shield-halved"></i> Bloquear Rango IP</button>'
    ].join(''));
  }

  function submitIPBan() {
    const ipRange = getValue('ipRange').trim();
    const reason = getValue('ipBanReason').trim();

    if (!ipRange || !reason) {
      notify('error', 'Rango IP y razon son obligatorios');
      return;
    }

    nuiJson('banIPRange', { ipRange, reason });
    closeInput();
  }

  function reduceBanTime(banId) {
    openInput('Reducir Ban', [
      '<div class="form-group">',
      '<label>Horas a reducir</label>',
      '<input type="number" id="reduceHours" value="24" min="1" max="8760" class="input-full">',
      '</div>',
      `<button class="btn btn-primary btn-full" onclick="submitReduceBan(${Number(banId) || 0})">`,
      '<i class="fas fa-clock"></i> Reducir Duracion</button>'
    ].join(''));
  }

  function submitReduceBan(banId) {
    const hours = toInt(getValue('reduceHours'), 24);
    if (!banId || banId <= 0 || !hours || hours <= 0) {
      notify('error', 'Datos invalidos para reducir ban');
      return;
    }

    nuiJson('reduceBan', { banId, hours });
    closeInput();

    if (typeof window.loadBans === 'function') {
      setTimeout(window.loadBans, 500);
    }
  }

  function openJailModal() {
    const target = getSelectedPlayer();
    if (!target) return;

    openInput('Encarcelar Jugador', [
      '<div class="form-group">',
      '<label>Tiempo (minutos)</label>',
      '<input type="number" id="jailTime" value="5" min="1" max="240" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Razon</label>',
      '<input type="text" id="jailReason" placeholder="Motivo" class="input-full">',
      '</div>',
      '<button class="btn btn-warning btn-full" onclick="submitJail()">',
      '<i class="fas fa-lock"></i> Aplicar Jail</button>'
    ].join(''));
  }

  function submitJail() {
    const target = getSelectedPlayer();
    if (!target) return;

    const time = toInt(getValue('jailTime'), 5);
    const reason = getValue('jailReason').trim();
    nuiJson('action', {
      action: 'jail',
      targetId: target.id,
      time,
      reason
    });
    closeInput();
  }

  function unjailPlayer() {
    const target = getSelectedPlayer();
    if (!target) return;
    nuiJson('action', { action: 'unjail', targetId: target.id });
  }

  function openMuteModal(type) {
    const target = getSelectedPlayer();
    if (!target) return;
    const muteType = (type === 'chat') ? 'chat' : 'voice';

    openInput(`Mutear ${muteType === 'chat' ? 'Chat' : 'Voz'}`, [
      '<div class="form-group">',
      '<label>Tiempo (minutos)</label>',
      '<input type="number" id="muteTime" value="10" min="1" max="240" class="input-full">',
      '</div>',
      `<button class="btn btn-warning btn-full" onclick="submitMute('${muteType}')">`,
      '<i class="fas fa-volume-xmark"></i> Aplicar Mute</button>'
    ].join(''));
  }

  function submitMute(type) {
    const target = getSelectedPlayer();
    if (!target) return;

    const time = toInt(getValue('muteTime'), 10);
    nuiJson('action', {
      action: type === 'chat' ? 'muteChat' : 'muteVoice',
      targetId: target.id,
      time
    });
    closeInput();
  }

  function unmutePlayer() {
    const target = getSelectedPlayer();
    if (!target) return;
    nuiJson('action', { action: 'unmute', targetId: target.id });
  }

  function openOfflineBanFor(identifier, playerName) {
    openOfflineBan();
    setTimeout(() => {
      const idEl = document.getElementById('banIdentifier');
      const nameEl = document.getElementById('banPlayerName');
      if (idEl) idEl.value = identifier || '';
      if (nameEl) nameEl.value = playerName || '';
    }, 0);
  }

  function viewPlayerHistory(identifier) {
    if (!identifier) {
      notify('error', 'Identifier invalido');
      return;
    }

    nuiJson('getPlayerHistory', { identifier }).then((history) => {
      const normalized = [];

      if (Array.isArray(history)) {
        for (const item of history) {
          normalized.push(item || {});
        }
      } else if (history && typeof history === 'object') {
        const buckets = ['bans', 'warnings', 'detections', 'transactions'];
        for (const bucket of buckets) {
          const rows = Array.isArray(history[bucket]) ? history[bucket] : [];
          for (const item of rows) {
            normalized.push({
              _bucket: bucket,
              ...(item || {})
            });
          }
        }
      }

      normalized.sort((a, b) => {
        const da = Date.parse(a.created_at || a.date || a.detection_date || a.warn_date || a.ban_date || '') || 0;
        const db = Date.parse(b.created_at || b.date || b.detection_date || b.warn_date || b.ban_date || '') || 0;
        return db - da;
      });

      const rows = normalized.map((h) => {
        const action =
          h.action ||
          h.type ||
          h.detection_type ||
          h.reason_type ||
          h._bucket ||
          'N/A';
        const detail =
          h.reason ||
          h.details ||
          h.punishment ||
          h.account ||
          '-';
        const date =
          h.created_at ||
          h.date ||
          h.detection_date ||
          h.warn_date ||
          h.ban_date ||
          'N/A';
        const actor =
          h.admin_name ||
          h.warned_by ||
          h.banned_by ||
          h.by ||
          'Sistema';
        return [
          '<tr>',
          `<td>${esc(action)}</td>`,
          `<td>${esc(detail)}</td>`,
          `<td>${esc(date)}</td>`,
          `<td>${esc(actor)}</td>`,
          '</tr>'
        ].join('');
      }).join('');

      const html = [
        '<div class="table-wrap">',
        '<table class="data-table">',
        '<thead><tr><th>Tipo</th><th>Detalle</th><th>Fecha</th><th>Admin</th></tr></thead>',
        `<tbody>${rows || '<tr><td colspan="4">Sin historial</td></tr>'}</tbody>`,
        '</table>',
        '</div>',
        '<div style="margin-top:12px">',
        `<button class="btn btn-danger btn-full" onclick="openOfflineBanFor('${esc(identifier)}','')">`,
        '<i class="fas fa-ban"></i> Banear Identifier</button>',
        '</div>'
      ].join('');

      openInput(`Historial: ${esc(identifier)}`, html);
    });
  }

  function legacySearchOfflinePlayers() {
    const search = getValue('offlineSearch').trim();
    if (!search) return;

    nuiJson('searchPlayer', { search }).then((results) => {
      const container = document.getElementById('searchResults');
      if (!container) return;

      const list = Array.isArray(results) ? results : [];
      container.innerHTML = list.map((p) => {
        const identifier = String(p.identifier || '');
        const name = String(p.player_name || 'Unknown');
        return [
          '<div class="search-result-item">',
          `<span>${esc(name)}</span>`,
          `<span class="text-muted">${esc(identifier.substring(0, 24))}...</span>`,
          `<span class="text-muted">${esc(p.last_seen || 'N/A')}</span>`,
          `<button class="btn btn-sm btn-primary" onclick="viewPlayerHistory('${esc(identifier)}')">Historial</button>`,
          `<button class="btn btn-sm btn-danger" onclick="openOfflineBanFor('${esc(identifier)}','${esc(name)}')">Ban</button>`,
          '</div>'
        ].join('');
      }).join('') || '<p>Sin resultados</p>';
    });
  }

  function legacyLoadWhitelist() {
    nuiJson('getWhitelist', {}).then((list) => {
      const container = document.getElementById('whitelistTable');
      if (!container) return;

      const rows = Array.isArray(list) ? list : [];
      container.innerHTML = rows.map((w) => {
        const identifier = String(w.identifier || '');
        return [
          '<tr>',
          `<td>${esc(w.player_name || 'N/A')}</td>`,
          `<td>${esc(identifier.substring(0, 25))}...</td>`,
          `<td>${esc(w.added_by || 'N/A')}</td>`,
          `<td>${esc(w.created_at || 'N/A')}</td>`,
          `<td><button class="btn btn-sm btn-danger" onclick="removeFromWhitelist('${esc(identifier)}')">Eliminar</button></td>`,
          '</tr>'
        ].join('');
      }).join('');
    });
  }

  function legacyOpenAddWhitelist() {
    openInput('Agregar a Whitelist', [
      '<div class="form-group">',
      '<label>Identifier</label>',
      '<input type="text" id="wlIdentifier" placeholder="license:xxxx" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Nombre</label>',
      '<input type="text" id="wlName" placeholder="Nombre del jugador" class="input-full">',
      '</div>',
      '<button class="btn btn-primary btn-full" onclick="submitAddWhitelist()">',
      '<i class="fas fa-user-plus"></i> Agregar</button>'
    ].join(''));
  }

  function submitAddWhitelist() {
    const identifier = getValue('wlIdentifier').trim();
    const playerName = getValue('wlName').trim();
    if (!identifier) {
      notify('error', 'Identifier requerido');
      return;
    }

    nuiJson('addWhitelist', { identifier, playerName });
    closeInput();
    if (typeof window.loadWhitelist === 'function') {
      setTimeout(window.loadWhitelist, 500);
    }
  }

  function removeFromWhitelist(identifier) {
    if (!identifier) return;
    if (!window.confirm('Eliminar de whitelist?')) return;

    nuiJson('removeWhitelist', { identifier });
    if (typeof window.loadWhitelist === 'function') {
      setTimeout(window.loadWhitelist, 500);
    }
  }

  function loadServerStats() {
    nuiJson('getServerStats', {}).then((stats) => {
      const container = document.getElementById('serverStatsGrid');
      if (!container) return;

      const safe = stats || {};
      container.innerHTML = [
        '<div class="stat-card"><div class="stat-icon gradient-blue"><i class="fas fa-users"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(`${safe.players || 0}/${safe.maxPlayers || 0}`)}</span><span class="stat-label">Jugadores Online</span></div></div>`,
        '<div class="stat-card"><div class="stat-icon gradient-green"><i class="fas fa-cube"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(`${safe.resourcesRunning || 0}/${safe.resourcesTotal || 0}`)}</span><span class="stat-label">Recursos Activos</span></div></div>`,
        '<div class="stat-card"><div class="stat-icon gradient-red"><i class="fas fa-ban"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(String(safe.activeBans || 0))}</span><span class="stat-label">Bans Activos</span></div></div>`,
        '<div class="stat-card"><div class="stat-icon gradient-orange"><i class="fas fa-shield-halved"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(String(safe.detectionsToday || 0))}</span><span class="stat-label">Detecciones Hoy</span></div></div>`,
        '<div class="stat-card"><div class="stat-icon gradient-purple"><i class="fas fa-chart-line"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(String(safe.actionsToday || 0))}</span><span class="stat-label">Acciones Admin Hoy</span></div></div>`,
        '<div class="stat-card"><div class="stat-icon gradient-yellow"><i class="fas fa-flag"></i></div><div class="stat-info"><span class="stat-value">',
        `${esc(String(safe.openReports || 0))}</span><span class="stat-label">Reportes Abiertos</span></div></div>`
      ].join('');
    });
  }

  function openPlayerGarage() {
    const target = getSelectedPlayer();
    if (!target) return;

    nuiJson('getPlayerGarage', { targetId: target.id }).then((vehicles) => {
      const list = Array.isArray(vehicles) ? vehicles : [];

      let html = '<div class="garage-list">';
      if (list.length > 0) {
        html += list.map((v) => {
          const plate = String(v.plate || '');
          const stored = !!v.stored;
          return [
            '<div class="garage-item">',
            `<span class="vehicle-name">${esc(v.vehicle || 'UNKNOWN')}</span>`,
            `<span class="vehicle-plate badge badge-info">${esc(plate)}</span>`,
            `<span class="badge ${stored ? 'badge-success' : 'badge-warning'}">${stored ? 'Guardado' : 'Fuera'}</span>`,
            `<button class="btn btn-sm btn-danger" onclick="deleteGarageVehicle('${esc(plate)}')">Eliminar</button>`,
            '</div>'
          ].join('');
        }).join('');
      } else {
        html += '<p>Sin vehiculos</p>';
      }
      html += '</div><hr>';
      html += [
        '<h4>Dar Vehiculo</h4>',
        '<input type="text" id="giveVehModel" placeholder="Modelo (ej: adder)" class="input-half">',
        '<input type="text" id="giveVehPlate" placeholder="Placa (opcional)" class="input-half">',
        '<button class="btn btn-primary btn-full" onclick="submitGiveVehicle()"><i class="fas fa-car"></i> Dar Vehiculo</button>'
      ].join('');

      openInput(`Garaje de ${esc(target.name)}`, html);
    });
  }

  function submitGiveVehicle() {
    const target = getSelectedPlayer();
    if (!target) return;

    const vehicle = getValue('giveVehModel').trim();
    if (!vehicle) {
      notify('error', 'Modelo de vehiculo requerido');
      return;
    }

    nuiJson('giveVehicle', {
      targetId: target.id,
      vehicle,
      plate: getValue('giveVehPlate').trim()
    });

    closeInput();
  }

  function deleteGarageVehicle(plate) {
    const target = getSelectedPlayer();
    if (!target || !plate) return;
    if (!window.confirm('Eliminar vehiculo del garaje?')) return;

    nuiJson('deleteGarageVehicle', { targetId: target.id, plate });
    closeInput();
  }

  function openPlayerLicenses() {
    const target = getSelectedPlayer();
    if (!target) return;

    nuiJson('getPlayerLicenses', { targetId: target.id }).then((licenses) => {
      const list = Array.isArray(licenses) ? licenses : [];

      let html = '<div class="licenses-list">';
      if (list.length > 0) {
        html += list.map((l) => [
          '<div class="license-item">',
          `<span class="badge badge-info">${esc(l.type || 'unknown')}</span>`,
          `<button class="btn btn-sm btn-danger" onclick="removeLicense('${esc(l.type || '')}')">Revocar</button>`,
          '</div>'
        ].join('')).join('');
      } else {
        html += '<p>Sin licencias</p>';
      }

      html += '</div><hr>';
      html += [
        '<h4>Dar Licencia</h4>',
        '<select id="licenseType" class="input-full">',
        '<option value="dmv">DMV (Conducir)</option>',
        '<option value="drive">Licencia Conducir</option>',
        '<option value="drive_bike">Licencia Moto</option>',
        '<option value="drive_truck">Licencia Camion</option>',
        '<option value="weapon">Licencia Armas</option>',
        '</select>',
        '<button class="btn btn-primary btn-full" onclick="submitGiveLicense()"><i class="fas fa-id-card"></i> Dar Licencia</button>'
      ].join('');

      openInput(`Licencias de ${esc(target.name)}`, html);
    });
  }

  function submitGiveLicense() {
    const target = getSelectedPlayer();
    if (!target) return;

    nuiJson('giveLicense', {
      targetId: target.id,
      license: getValue('licenseType')
    });

    closeInput();
  }

  function removeLicense(type) {
    const target = getSelectedPlayer();
    if (!target || !type) return;

    nuiJson('removeLicense', {
      targetId: target.id,
      license: type
    });

    closeInput();
  }

  function copyPlayerPosition() {
    const target = getSelectedPlayer();
    if (!target) return;
    nuiJson('copyPosition', { targetId: target.id });
  }

  function openScheduleAnnounce() {
    openInput('Programar Anuncio', [
      '<div class="form-group">',
      '<label>Mensaje</label>',
      '<input type="text" id="schedMsg" placeholder="Mensaje" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Enviar en (minutos)</label>',
      '<input type="number" id="schedDelay" value="5" min="1" max="1440" class="input-full">',
      '</div>',
      '<div class="form-group">',
      '<label>Repetir cada X min (0 = no repetir)</label>',
      '<input type="number" id="schedRepeat" value="0" min="0" max="1440" class="input-full">',
      '</div>',
      '<button class="btn btn-primary btn-full" onclick="submitScheduleAnnounce()">',
      '<i class="fas fa-calendar-check"></i> Programar</button>'
    ].join(''));
  }

  function submitScheduleAnnounce() {
    const message = getValue('schedMsg').trim();
    const delay = toInt(getValue('schedDelay'), 5);
    const repeat = toInt(getValue('schedRepeat'), 0);

    if (!message) {
      notify('error', 'Mensaje obligatorio');
      return;
    }

    nuiJson('scheduleAnnounce', {
      message,
      delay,
      repeat: repeat > 0 ? repeat : null
    });

    closeInput();
  }

  const AuditState = {
    offset: 0,
    limit: 100,
    total: 0
  };

  function readAuditFilters() {
    const action = getValue('auditAction').trim();
    const limit = toInt(getValue('auditLimit'), 100);
    AuditState.limit = Math.min(Math.max(limit || 100, 1), 200);

    const filters = {
      admin: getValue('auditAdmin').trim(),
      target: getValue('auditTarget').trim(),
      search: getValue('auditSearch').trim(),
      dateFrom: getValue('auditDateFrom').trim(),
      dateTo: getValue('auditDateTo').trim(),
      limit: AuditState.limit,
      offset: AuditState.offset
    };

    if (action) {
      filters.actions = [action];
    }

    return filters;
  }

  function parseDetails(detailsRaw) {
    if (!detailsRaw) return '';
    if (typeof detailsRaw === 'object') {
      try { return JSON.stringify(detailsRaw); } catch (_) { return String(detailsRaw); }
    }
    const text = String(detailsRaw);
    try {
      const parsed = JSON.parse(text);
      return JSON.stringify(parsed);
    } catch (_) {
      return text;
    }
  }

  function renderAuditRows(rows) {
    const tbody = document.getElementById('logsTableBody');
    if (!tbody) return;

    const html = (Array.isArray(rows) ? rows : [])
      .map((row) => {
        const created = esc(row.created_at || '');
        const admin = esc(row.admin_name || row.admin_id || 'N/A');
        const action = esc(row.action || 'N/A');
        const target = esc(row.target_name || row.target_id || 'N/A');
        const details = esc(parseDetails(row.details || ''));
        return `
          <tr>
            <td>${created}</td>
            <td>${admin}</td>
            <td><span class="badge badge-info">${action}</span></td>
            <td>${target}</td>
            <td><code style="white-space: pre-wrap; word-break: break-word;">${details}</code></td>
          </tr>
        `;
      })
      .join('');

    tbody.innerHTML = html || '<tr><td colspan="5">Sin resultados</td></tr>';
  }

  function updateAuditPageInfo() {
    const el = document.getElementById('auditPageInfo');
    if (!el) return;
    const page = Math.floor(AuditState.offset / AuditState.limit) + 1;
    const totalPages = Math.max(1, Math.ceil((AuditState.total || 0) / AuditState.limit));
    el.textContent = `Pagina ${page} / ${totalPages} (${AuditState.total || 0} registros)`;
  }

  function auditApply(resetOffset) {
    if (resetOffset !== false) {
      AuditState.offset = 0;
    }

    const filters = readAuditFilters();
    return nuiJson('queryLogs', filters).then((resp) => {
      if (!resp || resp.success !== true) {
        notify('error', permissionErrorText(resp, 'No se pudo consultar auditoria'));
        return;
      }

      AuditState.total = toInt(resp.total, 0) || 0;
      renderAuditRows(resp.rows || []);
      updateAuditPageInfo();
    });
  }

  function auditReset() {
    ['auditAdmin', 'auditTarget', 'auditSearch', 'auditAction', 'auditDateFrom', 'auditDateTo'].forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      if (el.tagName === 'SELECT') {
        el.selectedIndex = 0;
      } else {
        el.value = '';
      }
    });
    const limit = document.getElementById('auditLimit');
    if (limit) limit.value = '100';

    AuditState.offset = 0;
    AuditState.limit = 100;
    AuditState.total = 0;
    return auditApply(true);
  }

  function auditPrev() {
    if (AuditState.offset <= 0) return;
    AuditState.offset = Math.max(0, AuditState.offset - AuditState.limit);
    auditApply(false);
  }

  function auditNext() {
    if ((AuditState.offset + AuditState.limit) >= (AuditState.total || 0)) return;
    AuditState.offset = AuditState.offset + AuditState.limit;
    auditApply(false);
  }

  function downloadContent(filename, content, mimeType) {
    const blob = new Blob([content], { type: mimeType || 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename || 'download.txt';
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  function auditExport(format) {
    const normalized = (String(format || 'json').toLowerCase() === 'csv') ? 'csv' : 'json';
    const filters = readAuditFilters();
    return nuiJson('exportLogs', {
      format: normalized,
      maxRows: 2000,
      filters
    }).then((resp) => {
      if (!resp || resp.success !== true || typeof resp.content !== 'string') {
        notify('error', permissionErrorText(resp, 'No se pudo exportar auditoria'));
        return;
      }

      const mime = normalized === 'csv' ? 'text/csv;charset=utf-8' : 'application/json;charset=utf-8';
      downloadContent(resp.filename || `lyxpanel_logs.${normalized}`, resp.content, mime);
      notify('success', `Export ${normalized.toUpperCase()} generado`);
    });
  }

  // ---------------------------------------------------------------------------
  // v4.7 - Presets / Vehicle Pro Tools (UI wiring)
  // ---------------------------------------------------------------------------

  function hasPerm(key) {
    try {
      if (typeof window.perm === 'function') return window.perm(key) === true;
    } catch (_) {}
    try {
      if (window.adminPerms && typeof window.adminPerms === 'object') {
        return window.adminPerms[key] === true;
      }
    } catch (_) {}
    return false;
  }

  function sendPanelAction(payload) {
    if (typeof window.sendAction === 'function') {
      window.sendAction(payload || {});
      return;
    }
    if (typeof window.sendNUI === 'function') {
      window.sendNUI(payload || {});
      return;
    }
    if (typeof window.postNuiJson === 'function') {
      window.postNuiJson('action', payload || {});
    }
  }

  function setListHtml(id, html) {
    const el = document.getElementById(id);
    if (!el) return false;
    el.innerHTML = html;
    return true;
  }

  function renderEmpty(id, text) {
    setListHtml(id, `<div class="preset-empty">${esc(text || 'Sin datos')}</div>`);
  }

  function safeNowLabel(row) {
    const parts = [];
    const updated = row && (row.updated_at || row.updatedAt);
    const created = row && (row.created_at || row.createdAt);
    const when = updated || created;
    if (when) parts.push(String(when));
    const id = row && row.id;
    if (id) parts.push(`ID ${id}`);
    return sanitizeUiText(parts.join(' · '));
  }

  async function loadSelfPresets() {
    if (!document.getElementById('selfPresetsList')) return;
    if (!hasPerm('canManagePresets')) {
      renderEmpty('selfPresetsList', 'Sin permiso para administrar presets.');
      return;
    }

    setListHtml('selfPresetsList', '<div class="preset-empty">Cargando...</div>');
    const resp = await nuiJson('getSelfPresets', {});
    const rows = Array.isArray(resp) ? resp : [];

    if (!rows.length) {
      renderEmpty('selfPresetsList', 'No hay presets guardados.');
      return;
    }

    const html = rows
      .map((p) => {
        const id = toInt(p.id, 0);
        const name = sanitizeUiText(p.name || `preset_${id}`) || `preset_${id}`;
        const nameEnc = encodeURIComponent(name);
        const meta = safeNowLabel(p);
        return `
          <div class="preset-item">
            <div class="preset-meta">
              <div class="preset-name">${esc(name)}</div>
              <div class="preset-sub">${esc(meta)}</div>
            </div>
            <div class="preset-actions">
              <button class="btn btn-sm btn-primary" onclick="applySelfPreset(${id})">
                <i class="fas fa-play"></i> Aplicar
              </button>
              <button class="btn btn-sm btn-danger" onclick="deleteSelfPreset(${id}, '${nameEnc}')">
                <i class="fas fa-trash"></i>
              </button>
            </div>
          </div>
        `;
      })
      .join('');

    setListHtml('selfPresetsList', html);
  }

  async function saveSelfPreset() {
    if (!hasPerm('canManagePresets')) {
      notify('error', 'Sin permiso para administrar presets.');
      return;
    }

    const name = getValue('selfPresetName').trim();
    if (!name) {
      notify('error', 'Ingresa un nombre de preset.');
      return;
    }

    const snap = await nuiJson('getSelfSnapshot', {});
    if (!snap || snap.ok !== true || typeof snap.snapshot !== 'object') {
      notify('error', 'No se pudo obtener snapshot (cliente).');
      return;
    }

    sendPanelAction({ action: 'saveSelfPreset', name, data: snap.snapshot });
    notify('success', 'Guardando preset...');
    setTimeout(loadSelfPresets, 450);
  }

  function deleteSelfPreset(presetId, nameEnc) {
    if (!hasPerm('canManagePresets')) return;
    const id = toInt(presetId, 0);
    if (id <= 0) return;
    const name = nameEnc ? sanitizeUiText(decodeURIComponent(String(nameEnc))) : `#${id}`;

    const run = () => {
      sendPanelAction({ action: 'deleteSelfPreset', presetId: id });
      notify('warning', 'Eliminando preset...');
      setTimeout(loadSelfPresets, 450);
    };

    if (typeof window.showConfirm === 'function') {
      window.showConfirm('Eliminar preset', `Eliminar "${name}"?`, run, {
        icon: 'trash',
        buttonType: 'danger',
        buttonIcon: 'trash',
        buttonText: 'Eliminar'
      });
      return;
    }
    if (confirm(`Eliminar "${name}"?`)) run();
  }

  function applySelfPreset(presetId) {
    if (!hasPerm('canManagePresets')) return;
    const id = toInt(presetId, 0);
    if (id <= 0) return;
    sendPanelAction({ action: 'loadSelfPreset', presetId: id });
    notify('success', 'Aplicando preset...');
  }

  async function loadVehicleBuilds() {
    if (!document.getElementById('vehicleBuildsList')) return;
    if (!hasPerm('canManagePresets')) {
      renderEmpty('vehicleBuildsList', 'Sin permiso para administrar builds.');
      return;
    }

    setListHtml('vehicleBuildsList', '<div class="preset-empty">Cargando...</div>');
    const resp = await nuiJson('getVehicleBuilds', {});
    const rows = Array.isArray(resp) ? resp : [];

    if (!rows.length) {
      renderEmpty('vehicleBuildsList', 'No hay builds guardados.');
      return;
    }

    const html = rows
      .map((p) => {
        const id = toInt(p.id, 0);
        const name = sanitizeUiText(p.name || `build_${id}`) || `build_${id}`;
        const nameEnc = encodeURIComponent(name);
        const meta = safeNowLabel(p);
        return `
          <div class="preset-item">
            <div class="preset-meta">
              <div class="preset-name">${esc(name)}</div>
              <div class="preset-sub">${esc(meta)}</div>
            </div>
            <div class="preset-actions">
              <button class="btn btn-sm btn-primary" onclick="applyVehicleBuild(${id})">
                <i class="fas fa-wand-magic-sparkles"></i> Aplicar
              </button>
              <button class="btn btn-sm btn-danger" onclick="deleteVehicleBuild(${id}, '${nameEnc}')">
                <i class="fas fa-trash"></i>
              </button>
            </div>
          </div>
        `;
      })
      .join('');

    setListHtml('vehicleBuildsList', html);
  }

  async function saveVehicleBuild() {
    if (!hasPerm('canManagePresets')) {
      notify('error', 'Sin permiso para administrar builds.');
      return;
    }

    const name = getValue('vehicleBuildName').trim();
    if (!name) {
      notify('error', 'Ingresa un nombre de build.');
      return;
    }

    const snap = await nuiJson('getCurrentVehicleBuild', {});
    if (!snap || snap.ok !== true || typeof snap.build !== 'object') {
      notify('error', snap && snap.error === 'no_vehicle' ? 'No estas en un vehiculo.' : 'No se pudo leer build actual.');
      return;
    }

    sendPanelAction({ action: 'saveVehicleBuild', name, build: snap.build });
    notify('success', 'Guardando build...');
    setTimeout(loadVehicleBuilds, 450);
  }

  function deleteVehicleBuild(buildId, nameEnc) {
    if (!hasPerm('canManagePresets')) return;
    const id = toInt(buildId, 0);
    if (id <= 0) return;
    const name = nameEnc ? sanitizeUiText(decodeURIComponent(String(nameEnc))) : `#${id}`;

    const run = () => {
      sendPanelAction({ action: 'deleteVehicleBuild', buildId: id });
      notify('warning', 'Eliminando build...');
      setTimeout(loadVehicleBuilds, 450);
    };

    if (typeof window.showConfirm === 'function') {
      window.showConfirm('Eliminar build', `Eliminar "${name}"?`, run, {
        icon: 'trash',
        buttonType: 'danger',
        buttonIcon: 'trash',
        buttonText: 'Eliminar'
      });
      return;
    }
    if (confirm(`Eliminar "${name}"?`)) run();
  }

  function applyVehicleBuild(buildId) {
    const id = toInt(buildId, 0);
    if (id <= 0) return;
    sendPanelAction({ action: 'applyVehicleBuild', buildId: id });
    notify('success', 'Aplicando build...');
  }

  async function loadVehicleFavorites() {
    if (!document.getElementById('vehicleFavoritesList')) return;
    if (!hasPerm('canManagePresets')) {
      renderEmpty('vehicleFavoritesList', 'Sin permiso para administrar favoritos.');
      return;
    }

    setListHtml('vehicleFavoritesList', '<div class="preset-empty">Cargando...</div>');
    const resp = await nuiJson('getVehicleFavorites', {});
    const rows = Array.isArray(resp) ? resp : [];

    if (!rows.length) {
      renderEmpty('vehicleFavoritesList', 'No hay favoritos guardados.');
      return;
    }

    const html = rows
      .map((f) => {
        const id = toInt(f.id, 0);
        const model = sanitizeUiText(f.model || '') || 'unknown';
        const label = sanitizeUiText(f.label || '') || model;
        const labelEnc = encodeURIComponent(label);
        const meta = safeNowLabel(f);
        return `
          <div class="preset-item">
            <div class="preset-meta">
              <div class="preset-name">${esc(label)} <span class="preset-chip"><code>${esc(model)}</code></span></div>
              <div class="preset-sub">${esc(meta)}</div>
            </div>
            <div class="preset-actions">
              <button class="btn btn-sm btn-primary" onclick="spawnFavoriteVehicle('${esc(model)}')">
                <i class="fas fa-car"></i> Spawn
              </button>
              <button class="btn btn-sm btn-danger" onclick="removeVehicleFavorite(${id}, '${labelEnc}')">
                <i class="fas fa-trash"></i>
              </button>
            </div>
          </div>
        `;
      })
      .join('');

    setListHtml('vehicleFavoritesList', html);
  }

  function addVehicleFavorite() {
    if (!hasPerm('canManagePresets')) return;
    const model = getValue('vehicleFavoriteModel').trim();
    const label = getValue('vehicleFavoriteLabel').trim();
    if (!model) {
      notify('error', 'Ingresa el modelo.');
      return;
    }
    sendPanelAction({ action: 'addVehicleFavorite', model, label: label || model });
    notify('success', 'Agregando favorito...');
    setTimeout(loadVehicleFavorites, 450);
  }

  function removeVehicleFavorite(favoriteId, labelEnc) {
    if (!hasPerm('canManagePresets')) return;
    const id = toInt(favoriteId, 0);
    if (id <= 0) return;
    const label = labelEnc ? sanitizeUiText(decodeURIComponent(String(labelEnc))) : `#${id}`;

    const run = () => {
      sendPanelAction({ action: 'removeVehicleFavorite', favoriteId: id });
      notify('warning', 'Eliminando favorito...');
      setTimeout(loadVehicleFavorites, 450);
    };

    if (typeof window.showConfirm === 'function') {
      window.showConfirm('Eliminar favorito', `Eliminar "${label}"?`, run, {
        icon: 'trash',
        buttonType: 'danger',
        buttonIcon: 'trash',
        buttonText: 'Eliminar'
      });
      return;
    }
    if (confirm(`Eliminar "${label}"?`)) run();
  }

  function spawnFavoriteVehicle(model) {
    const clean = sanitizeUiText(model || '').trim();
    if (!clean) return;
    if (typeof window.spawnCustomVehicle === 'function') {
      window.spawnCustomVehicle(clean);
    } else {
      sendPanelAction({ action: 'spawnVehicle', model: clean });
    }
  }

  async function loadVehicleSpawnHistory() {
    if (!document.getElementById('vehicleSpawnHistoryList')) return;
    if (!hasPerm('canManagePresets')) {
      renderEmpty('vehicleSpawnHistoryList', 'Sin permiso para ver historial.');
      return;
    }

    const limitEl = document.getElementById('vehicleSpawnHistoryLimit');
    const limit = limitEl ? toInt(limitEl.value, 50) : 50;

    setListHtml('vehicleSpawnHistoryList', '<div class="preset-empty">Cargando...</div>');
    const resp = await nuiJson('getVehicleSpawnHistory', { limit });
    const rows = Array.isArray(resp) ? resp : [];

    if (!rows.length) {
      renderEmpty('vehicleSpawnHistoryList', 'Sin historial por ahora.');
      return;
    }

    const html = rows
      .map((h) => {
        const model = sanitizeUiText(h.model || '') || 'unknown';
        const label = sanitizeUiText(h.label || '') || model;
        const created = sanitizeUiText(h.created_at || '');
        const target = sanitizeUiText(h.target_name || '');
        const targetPart = target ? ` · Target: ${target}` : '';
        const meta = `${created}${targetPart}`.trim() || safeNowLabel(h);
        const favLabelEnc = encodeURIComponent(label);
        return `
          <div class="preset-item">
            <div class="preset-meta">
              <div class="preset-name">${esc(label)} <span class="preset-chip"><code>${esc(model)}</code></span></div>
              <div class="preset-sub">${esc(meta)}</div>
            </div>
            <div class="preset-actions">
              <button class="btn btn-sm btn-primary" onclick="spawnFavoriteVehicle('${esc(model)}')">
                <i class="fas fa-rotate-left"></i> Repetir
              </button>
              <button class="btn btn-sm btn-secondary" onclick="addVehicleFavoriteFromHistory('${esc(model)}', '${favLabelEnc}')">
                <i class="fas fa-star"></i> Fav
              </button>
            </div>
          </div>
        `;
      })
      .join('');

    setListHtml('vehicleSpawnHistoryList', html);
  }

  function addVehicleFavoriteFromHistory(model, labelEnc) {
    if (!hasPerm('canManagePresets')) return;
    const m = sanitizeUiText(model || '').trim();
    const label = labelEnc ? sanitizeUiText(decodeURIComponent(String(labelEnc))) : m;
    if (!m) return;
    sendPanelAction({ action: 'addVehicleFavorite', model: m, label: label || m });
    notify('success', 'Agregando a favoritos...');
    setTimeout(loadVehicleFavorites, 450);
  }

  // Register functions globally for HTML onclick handlers.
  window.nuiJson = nuiJson;
  window.openOfflineBan = openOfflineBan;
  window.submitOfflineBan = submitOfflineBan;
  window.openIPBan = openIPBan;
  window.submitIPBan = submitIPBan;
  window.reduceBanTime = reduceBanTime;
  window.submitReduceBan = submitReduceBan;
  window.openJailModal = openJailModal;
  window.submitJail = submitJail;
  window.unjailPlayer = unjailPlayer;
  window.openMuteModal = openMuteModal;
  window.submitMute = submitMute;
  window.unmutePlayer = unmutePlayer;
  window.openOfflineBanFor = openOfflineBanFor;
  window.viewPlayerHistory = viewPlayerHistory;
  window.submitAddWhitelist = submitAddWhitelist;
  window.removeFromWhitelist = removeFromWhitelist;
  window.loadServerStats = loadServerStats;
  window.openPlayerGarage = openPlayerGarage;
  window.submitGiveVehicle = submitGiveVehicle;
  window.deleteGarageVehicle = deleteGarageVehicle;
  window.openPlayerLicenses = openPlayerLicenses;
  window.submitGiveLicense = submitGiveLicense;
  window.removeLicense = removeLicense;
  window.copyPlayerPosition = copyPlayerPosition;
  window.openScheduleAnnounce = openScheduleAnnounce;
  window.submitScheduleAnnounce = submitScheduleAnnounce;
  window.auditApply = auditApply;
  window.auditReset = auditReset;
  window.auditPrev = auditPrev;
  window.auditNext = auditNext;
  window.auditExport = auditExport;
  window.loadSelfPresets = loadSelfPresets;
  window.saveSelfPreset = saveSelfPreset;
  window.deleteSelfPreset = deleteSelfPreset;
  window.applySelfPreset = applySelfPreset;
  window.loadVehicleBuilds = loadVehicleBuilds;
  window.saveVehicleBuild = saveVehicleBuild;
  window.deleteVehicleBuild = deleteVehicleBuild;
  window.applyVehicleBuild = applyVehicleBuild;
  window.loadVehicleFavorites = loadVehicleFavorites;
  window.addVehicleFavorite = addVehicleFavorite;
  window.removeVehicleFavorite = removeVehicleFavorite;
  window.loadVehicleSpawnHistory = loadVehicleSpawnHistory;
  window.spawnFavoriteVehicle = spawnFavoriteVehicle;
  window.addVehicleFavoriteFromHistory = addVehicleFavoriteFromHistory;
  window.permissionsLoad = permissionsLoad;
  window.permissionsLoadRole = permissionsLoadRole;
  window.permissionsSetRole = permissionsSetRole;
  window.permissionsResetRole = permissionsResetRole;
  window.permissionsLoadIndividual = permissionsLoadIndividual;
  window.permissionsSetIndividual = permissionsSetIndividual;
  window.permissionsResetIndividual = permissionsResetIndividual;
  window.accessReload = accessReload;
  window.accessGrant = accessGrant;
  window.accessRemove = accessRemove;

  if (typeof window.searchOfflinePlayers !== 'function') {
    window.searchOfflinePlayers = legacySearchOfflinePlayers;
  }
  if (typeof window.loadWhitelist !== 'function') {
    window.loadWhitelist = legacyLoadWhitelist;
  }
  if (typeof window.openAddWhitelist !== 'function') {
    window.openAddWhitelist = legacyOpenAddWhitelist;
  }

  bindPermissionEditorUi();

  if (typeof window.loadLogs !== 'function') {
    window.loadLogs = function () { return auditApply(true); };
  } else {
    const oldLoadLogs = window.loadLogs;
    window.loadLogs = function () {
      const result = auditApply(true);
      if (result && typeof result.catch === 'function') {
        result.catch(() => oldLoadLogs());
      }
      return result;
    };
  }

  console.log('[LyxPanel] Extended JS loaded (v4.6)');
})();

