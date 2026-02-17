/* LyxPanel UI - app.js */

let adminPerms = {};
let uiConfig = {};
let currentPlayers = [];
let selectedPlayer = null;
let noclipActive = false,
  godmodeActive = false,
  invisibleActive = false;
// -----------------------------------------------------------------------------
// NUI SECURITY v4.1
// -----------------------------------------------------------------------------
const NUISecurity = {
  requestCount: 0,
  lastRequestTime: 0,
  maxRequestsPerSecond: 10,
  blockedUntil: 0,

  // Rate limit check
  canSendRequest: function () {
    const now = Date.now();

    // Check if blocked
    if (now < this.blockedUntil) {
      console.warn('[LyxPanel] Rate limited - wait before sending more requests');
      return false;
    }

    // Reset counter every second
    if (now - this.lastRequestTime > 1000) {
      this.requestCount = 0;
      this.lastRequestTime = now;
    }

    this.requestCount++;

    // Block if too many requests
    if (this.requestCount > this.maxRequestsPerSecond) {
      this.blockedUntil = now + 2000; // Block for 2 seconds
      console.warn('[LyxPanel] Too many requests - rate limited');
      return false;
    }

    return true;
  },

  // Sanitize user input
  sanitize: function (input) {
    if (typeof input !== 'string') return input;
    return input
      .replace(/[<>]/g, '') // Remove HTML tags
      .replace(/['";]/g, '') // Remove SQL injection chars
      .substring(0, 500); // Limit length
  }
};

// NUI Listener
window.addEventListener("message", (e) => {
  const d = e.data;
  if (d.action === "open") openPanel(d);
  else if (d.action === "updateStats") updateStats(d.stats);
  else if (d.action === "updatePlayers") updatePlayers(d.players);
  else if (d.action === "close") {
    document.getElementById("app").classList.add("hidden");
  }
});

function openPanel(data) {
  try {
    document.getElementById("app").classList.remove("hidden");
    adminPerms = data.permissions || {};
    uiConfig = data.config || {};
    document.getElementById("adminRole").textContent = data.group || "Admin";
    refreshDependencyStatus(data || {});
    buildCategories();
    buildWorld();
    refreshData();
  } catch (e) {
    console.error("[LyxPanel] Error opening panel:", e);
    fetch(`https://${GetParentResourceName()}/close`, {
      method: "POST",
      body: "{}",
    });
  }
}

function closePanel() {
  document.getElementById("app").classList.add("hidden");
  fetch(`https://${GetParentResourceName()}/close`, {
    method: "POST",
    body: "{}",
  });
}

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (!document.getElementById("playerModal").classList.contains("hidden"))
      closeModal();
    else if (
      !document.getElementById("inputModal").classList.contains("hidden")
    )
      closeInputModal();
    else closePanel();
  }
});

function refreshData() {
  fetch(`https://${GetParentResourceName()}/refresh`, {
    method: "POST",
    body: "{}",
  });
}

// updateStats function defined at line ~872 with enhanced uptime support

function updatePlayers(players) {
  currentPlayers = players;
  renderPlayersTable(players);
  updatePlayerSelects(players);
}

function renderPlayersTable(players) {
  const tb = document.getElementById("playersTableBody");

  // DOM Optimization: Use document fragment to batch DOM updates
  const fragment = document.createDocumentFragment();

  players.forEach((p) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
            <td><span class="badge badge-info">${p.id}</span></td>
            <td>${esc(p.name)}</td>
            <td>${esc(p.job)}</td>
            <td>$${fmt(p.money + p.bank)}</td>
            <td>${p.ping}ms</td>
            <td><button class="btn btn-primary btn-sm" onclick="openPlayerModal(${p.id
      })"><i class="fas fa-eye"></i></button></td>`;
    fragment.appendChild(tr);
  });

  // Single DOM update instead of multiple innerHTML appends
  tb.innerHTML = "";
  tb.appendChild(fragment);
}

function filterPlayers() {
  const s = document.getElementById("playerSearch").value.toLowerCase();
  renderPlayersTable(
    currentPlayers.filter(
      (p) => p.name.toLowerCase().includes(s) || p.id.toString().includes(s)
    )
  );
}

function updatePlayerSelects(players) {
  const opts = players
    .map((p) => `<option value="${p.id}">${p.id} - ${esc(p.name)}</option>`)
    .join("");
  [
    "ecoTargetPlayer",
    "ecoFromPlayer",
    "ecoToPlayer",
    "toolTargetPlayer",
    "modelTargetPlayer",
  ].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = opts;
  });
}

// Build categories
function buildCategories() {
  // Vehicles
  const vehCont = document.getElementById("vehicleCategories");
  if (vehCont && uiConfig.vehicles) {
    vehCont.innerHTML = "";

    // Custom Vehicles (from [cars] folder) - shown first with special styling
    if (uiConfig.customVehicles && uiConfig.customVehicles.length > 0) {
      vehCont.innerHTML += `
            <div class="category-card custom-vehicles-category">
                <div class="category-header" onclick="toggleCategory(this)">
                    <i class="fas fa-star"></i> Personalizados 
                    <span class="custom-vehicles-badge">${uiConfig.customVehicles.length}</span>
                    <i class="fas fa-chevron-down" style="margin-left: auto;"></i>
                </div>
                <div class="category-items" id="vehCatCustom">
                    <div class="custom-vehicles-search">
                        <input type="text" id="customVehicleSearch" placeholder="Buscar vehiculo..." oninput="filterCustomVehicles()">
                    </div>
                    <div id="customVehiclesList">
                        ${uiConfig.customVehicles
          .map(
            (v) =>
              `<div class="category-item" onclick="spawnCustomVehicle('${v.name
              }')" title="Spawn: ${v.name}" data-name="${v.name.toLowerCase()}" data-label="${(v.label || v.name).toLowerCase()}">${v.label || v.name}</div>`
          )
          .join("")}
                    </div>
                </div>
            </div>`;
    } else {
      // Show empty state if no custom vehicles
      vehCont.innerHTML += `
            <div class="category-card custom-vehicles-category">
                <div class="category-header" onclick="toggleCategory(this)">
                    <i class="fas fa-star"></i> Personalizados 
                    <span class="custom-vehicles-badge">0</span>
                    <i class="fas fa-chevron-down" style="margin-left: auto;"></i>
                </div>
                <div class="category-items">
                    <div class="custom-vehicles-empty">
                        <i class="fas fa-car"></i>
                        <p><strong>No se detectaron vehiculos personalizados</strong></p>
                        <p>Agrega recursos de vehiculos a la carpeta [cars]</p>
                    </div>
                </div>
            </div>`;
    }

    // Standard vehicles
    uiConfig.vehicles.forEach((cat, i) => {
      vehCont.innerHTML += `
            <div class="category-card">
                <div class="category-header" onclick="toggleCategory(this)">
                    ${cat.category} <i class="fas fa-chevron-down"></i>
                </div>
                <div class="category-items" id="vehCat${i}">
                    ${cat.vehicles
          .map(
            (v) =>
              `<div class="category-item" onclick="spawnVehicle('${v}')">${v}</div>`
          )
          .join("")}
                </div>
            </div>`;
    });
  }
  // Weapons
  const wepCont = document.getElementById("weaponCategories");
  if (wepCont && uiConfig.weapons) {
    wepCont.innerHTML = "";
    uiConfig.weapons.forEach((cat, i) => {
      wepCont.innerHTML += `
            <div class="category-card">
                <div class="category-header" onclick="toggleCategory(this)">
                    ${cat.category} <i class="fas fa-chevron-down"></i>
                </div>
                <div class="category-items" id="wepCat${i}">
                    ${cat.items
          .map(
            (w) =>
              `<div class="category-item" onclick="giveWeaponSelf('${w.name}')">${w.label}</div>`
          )
          .join("")}
                </div>
            </div>`;
    });
  }
}

function toggleCategory(el) {
  el.classList.toggle("open");
  el.nextElementSibling.classList.toggle("open");
}

function buildWorld() {
  // Weather
  const ws = document.getElementById("weatherSelect");
  if (ws && uiConfig.weather) {
    ws.innerHTML = uiConfig.weather.types
      .map((w) => `<option value="${w}">${w}</option>`)
      .join("");
  }
  // Spawn points
  const sp = document.getElementById("spawnPointsList");
  if (sp && uiConfig.spawnPoints) {
    sp.innerHTML = uiConfig.spawnPoints
      .map(
        (p) =>
          `<button class="spawn-point-btn" onclick="teleportTo(${p.x}, ${p.y}, ${p.z})">${p.name}</button>`
      )
      .join("");
  }
  // Themes
  const th = document.getElementById("themesList");
  if (th && uiConfig.themes) {
    th.innerHTML = uiConfig.themes
      .map(
        (t) =>
          `<button class="theme-btn" style="background:${t.bg};color:${t.primary}" onclick="setTheme('${t.id}')">${t.name}</button>`
      )
      .join("");
  }
}

// Player Modal
function openPlayerModal(id) {
  fetch(`https://${GetParentResourceName()}/getPlayerDetails`, {
    method: "POST",
    body: JSON.stringify({ playerId: id }),
  })
    .then((r) => r.json())
    .then((p) => {
      if (!p || (!p.id && !p.identifier)) {
        console.error("[LyxPanel] Invalid player details received");
        return;
      }
      selectedPlayer = p;
      document.getElementById("modalPlayerName").textContent = p.name;

      // Info tab
      document.getElementById("playerInfoGrid").innerHTML = `
            <div class="info-item"><label>ID</label><span>${p.id || "?"
        }</span></div>
            <div class="info-item"><label>Ping</label><span>${p.ping || 0
        }ms</span></div>
            <div class="info-item"><label>Trabajo</label><span>${p.job?.label || "N/A"
        } (${p.job?.grade || 0})</span></div>
            <div class="info-item"><label>Grupo</label><span>${p.group || "user"
        }</span></div>
            <div class="info-item"><label>Efectivo</label><span>$${fmt(
          p.accounts?.money || 0
        )}</span></div>
            <div class="info-item"><label>Banco</label><span>$${fmt(
          p.accounts?.bank || 0
        )}</span></div>
            <div class="info-item"><label>Negro</label><span>$${fmt(
          p.accounts?.black || 0
        )}</span></div>
            <div class="info-item"><label>Salud</label><span>${p.health || 0}/${p.maxHealth || 200
        }</span></div>
            <div class="info-item"><label>Armadura</label><span>${p.armor || 0
        }</span></div>
            <div class="info-item"><label>Vehiculo</label><span>${p.vehicle || "Ninguno"
        }</span></div>
            <div class="info-item"><label>Coords</label><span>${(
          p.coords?.x || 0
        ).toFixed(1)}, ${(p.coords?.y || 0).toFixed(1)}, ${(
          p.coords?.z || 0
        ).toFixed(1)}</span></div>
            <div class="info-item"><label>License</label><span>${p.identifiers?.license?.substring(0, 20) || "N/A"
        }...</span></div>
        `;

      // Helper function to check permissions
      const perm = (key) => adminPerms && adminPerms[key] === true;

      // Actions tab
      document.getElementById("playerActionsGrid").innerHTML = `
            ${perm("canGoto")
          ? `<button class="player-action-btn" onclick="act('teleportTo')"><i class="fas fa-location-arrow"></i>Ir a</button>`
          : ""
        }
            ${perm("canBring")
          ? `<button class="player-action-btn" onclick="act('bring')"><i class="fas fa-user-plus"></i>Traer</button>`
          : ""
        }
            ${perm("canHeal")
          ? `<button class="player-action-btn success" onclick="act('heal')"><i class="fas fa-heart"></i>Curar</button>`
          : ""
        }
            ${perm("canRevive")
          ? `<button class="player-action-btn success" onclick="act('revive')"><i class="fas fa-star-of-life"></i>Revivir</button>`
          : ""
        }
            ${perm("canGiveArmor")
          ? `<button class="player-action-btn" onclick="openArmorInput()"><i class="fas fa-shield"></i>Armadura</button>`
          : ""
        }
            ${perm("canGiveMoney")
          ? `<button class="player-action-btn" onclick="openMoneyInput()"><i class="fas fa-dollar-sign"></i>Dar $</button>`
          : ""
        }
            ${perm("canGiveWeapons")
          ? `<button class="player-action-btn" onclick="openWeaponInput()"><i class="fas fa-gun"></i>Dar Arma</button>`
          : ""
        }
            ${perm("canGiveWeapons")
          ? `<button class="player-action-btn" onclick="openAmmoInput()"><i class="fas fa-bullseye"></i>Dar Balas</button>`
          : ""
        }
            ${perm("canSpawnVehicles")
          ? `<button class="player-action-btn" onclick="openVehicleInput()"><i class="fas fa-car"></i>Vehiculo</button>`
          : ""
        }
            ${perm("canSetJob")
          ? `<button class="player-action-btn" onclick="openJobInput()"><i class="fas fa-briefcase"></i>Trabajo</button>`
          : ""
        }
            ${perm("canGiveItems")
          ? `<button class="player-action-btn" onclick="openItemInput()"><i class="fas fa-box"></i>Item</button>`
          : ""
        }
            ${perm("canFreeze")
          ? `<button class="player-action-btn warning" onclick="act('freeze', true)"><i class="fas fa-snowflake"></i>Freeze</button>`
          : ""
        }
            ${perm("canFreeze")
          ? `<button class="player-action-btn" onclick="act('freeze', false)"><i class="fas fa-fire"></i>Unfreeze</button>`
          : ""
        }
            ${perm("canSpectate")
          ? `<button class="player-action-btn" onclick="act('spectate')"><i class="fas fa-binoculars"></i>Spectate</button>`
          : ""
        }
            ${perm("canScreenshot")
          ? `<button class="player-action-btn" onclick="act('screenshot')"><i class="fas fa-camera"></i>Screenshot</button>`
          : ""
        }
            ${perm("canKill")
          ? `<button class="player-action-btn warning" onclick="act('kill')"><i class="fas fa-skull"></i>Kill</button>`
          : ""
        }
            ${perm("canSlap")
          ? `<button class="player-action-btn warning" onclick="act('slap')"><i class="fas fa-hand-back-fist"></i>Slap</button>`
          : ""
        }
            ${perm("canClearInventory")
          ? `<button class="player-action-btn warning" onclick="act('clearInventory')"><i class="fas fa-trash"></i>Limpiar Inv</button>`
          : ""
        }
            ${perm("canRemoveWeapons")
          ? `<button class="player-action-btn warning" onclick="act('removeAllWeapons')"><i class="fas fa-gun"></i>Quitar Armas</button>`
          : ""
        }
            ${perm("canWarn")
          ? `<button class="player-action-btn warning" onclick="openWarnInput()"><i class="fas fa-exclamation-triangle"></i>Warn</button>`
          : ""
        }
            ${perm("canKick")
          ? `<button class="player-action-btn danger" onclick="openKickInput()"><i class="fas fa-door-open"></i>Kick</button>`
          : ""
        }
            ${perm("canBan")
          ? `<button class="player-action-btn danger" onclick="openBanInput()"><i class="fas fa-ban"></i>Ban</button>`
          : ""
        }
            ${perm("canKick")
          ? `<button class="player-action-btn warning" onclick="openAdminJailInput()"><i class="fas fa-lock"></i>Admin Jail</button>`
          : ""
        }
            ${perm("canSetModel")
          ? `<button class="player-action-btn warning" onclick="act('clearPed')"><i class="fas fa-user-slash"></i>Clear Ped</button>`
          : ""
        }
            ${perm("canBan")
          ? `<button class="player-action-btn danger" onclick="confirmWipePlayer()"><i class="fas fa-trash-can"></i>Wipe Data</button>`
          : ""
        }
        `;

      // Inventory tab
      const inv = document.getElementById("playerInventory");
      inv.innerHTML =
        (p.inventory || [])
          .filter((i) => i.count > 0)
          .map(
            (i) =>
              `<div class="inv-item">${i.label}<br><span class="count">x${i.count}</span></div>`
          )
          .join("") || "<p>Sin items</p>";

      // Notes tab
      const notes = document.getElementById("playerNotes");
      notes.innerHTML =
        (p.notes || [])
          .map(
            (n) =>
              `<div class="info-item"><label>${n.admin_name} - ${n.created_at
              }</label><span>${esc(n.note)}</span></div>`
          )
          .join("") || "<p>Sin notas</p>";

      document.getElementById("playerModal").classList.remove("hidden");
      showTab("info");
    })
    .catch((e) => console.error("[LyxPanel] Error getting player details:", e));
}

function closeModal() {
  document.getElementById("playerModal").classList.add("hidden");
  selectedPlayer = null;
}
function closeInputModal() {
  document.getElementById("inputModal").classList.add("hidden");
}

// Tabs
document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.onclick = () => showTab(btn.dataset.tab);
});

function showTab(name) {
  document
    .querySelectorAll(".tab-btn")
    .forEach((b) => b.classList.remove("active"));
  document
    .querySelectorAll(".tab-content")
    .forEach((c) => c.classList.remove("active"));
  document
    .querySelector(`.tab-btn[data-tab="${name}"]`)
    ?.classList.add("active");
  document
    .getElementById("tab" + name.charAt(0).toUpperCase() + name.slice(1))
    ?.classList.add("active");
}

// Actions
function act(a, extra) {
  if (!selectedPlayer) {
    console.error("[LyxPanel] No selected player!");
    return;
  }
  const d = { action: a, targetId: selectedPlayer.id };
  if (extra !== undefined) d.freeze = extra;
  sendAction(d);
}

// NOTE:
// showConfirm() is implemented later with the unified modal system.
// Keep a single implementation to avoid behavior drift.

function sendAction(d) {
  if (typeof NUISecurity !== "undefined" && !NUISecurity.canSendRequest()) {
    return;
  }
  fetch(`https://${GetParentResourceName()}/action`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(d || {}),
  });
}

// Quick actions
function toggleNoclip() {
  noclipActive = !noclipActive;
  document
    .getElementById("btnNoclip")
    ?.classList.toggle("active", noclipActive);
  sendAction({ action: "noclip" });
}
function toggleGodmode() {
  godmodeActive = !godmodeActive;
  document
    .getElementById("btnGodmode")
    ?.classList.toggle("active", godmodeActive);
  sendAction({ action: "godmode" });
}
function toggleInvisible() {
  invisibleActive = !invisibleActive;
  document
    .getElementById("btnInvisible")
    ?.classList.toggle("active", invisibleActive);
  sendAction({ action: "invisible" });
}

// New toggles: speedboost, nitro, vehicleGodmode
let speedboostActive = false;
function toggleSpeedboost() {
  speedboostActive = !speedboostActive;
  document
    .getElementById("btnSpeedboost")
    ?.classList.toggle("active", speedboostActive);
  sendAction({ action: "speedboost" });
  Toast.info('Speedboost', speedboostActive ? 'Activado' : 'Desactivado');
}

let nitroActive = false;
function toggleNitro() {
  nitroActive = !nitroActive;
  document
    .getElementById("btnNitro")
    ?.classList.toggle("active", nitroActive);
  sendAction({ action: "nitro" });
  Toast.info('Nitro', nitroActive ? 'Activado' : 'Desactivado');
}

let vehicleGodmodeActive = false;
function toggleVehicleGodmode() {
  vehicleGodmodeActive = !vehicleGodmodeActive;
  document
    .getElementById("btnVehicleGodmode")
    ?.classList.toggle("active", vehicleGodmodeActive);
  sendAction({ action: "vehicleGodmode" });
  Toast.info('Vehicle Godmode', vehicleGodmodeActive ? 'Activado' : 'Desactivado');
}
let staffStatusActive = false;
function toggleStaffStatus() {
  staffStatusActive = !staffStatusActive;
  document
    .getElementById("btnStaffStatus")
    ?.classList.toggle("active", staffStatusActive);
  fetch(`https://${GetParentResourceName()}/toggleStaffStatus`, {
    method: "POST",
    body: JSON.stringify({
      role: adminPerms?.group?.toUpperCase() || "STAFF",
      active: staffStatusActive,
    }),
  });
}
function healSelf() {
  sendAction({ action: "heal", targetId: -1 });
}
function reviveSelf() {
  sendAction({ action: "revive", targetId: -1 });
  showToast("success", "Intentando revivirte...");
}
function setArmorSelf() {
  sendAction({ action: "setArmor", targetId: -1, amount: 100 });
  showToast("success", "Armadura al 100%");
}
function disarmSelf() {
  sendAction({ action: "removeAllWeapons", targetId: -1 });
  showToast("info", "Armas removidas");
}
function teleportMarker() {
  sendAction({ action: "teleportMarker" });
}
function teleportBack() {
  sendAction({ action: "teleportBack" });
  showToast("info", "Volviendo a posicion previa...");
}
function reviveRadiusPrompt() {
  showInput("Revive Radius", "Radio en metros (5-250)", (rawRadius) => {
    let radius = parseInt(rawRadius, 10);
    if (!Number.isFinite(radius)) {
      showToast("error", "Radio invalido");
      return;
    }
    radius = Math.max(5, Math.min(250, radius));
    showConfirm(
      "Confirmar Revive Radius",
      `Revivir jugadores en ${radius}m alrededor tuyo?`,
      () => {
        sendAction({ action: "reviveRadius", radius: radius });
        showToast("success", `Revive radius enviado (${radius}m)`);
      }
    );
  }, {
    placeholder: "25",
    defaultValue: "25",
    submitText: "Continuar"
  });
}
function screenshotBatchPrompt() {
  const defaultIds = selectedPlayer && selectedPlayer.id ? String(selectedPlayer.id) : "";
  showInput("Screenshot Lote", "IDs separados por coma (ej: 12,15,20)", (rawIds) => {
    const ids = String(rawIds || "")
      .split(",")
      .map((x) => parseInt(x.trim(), 10))
      .filter((x) => Number.isFinite(x) && x > 0);
    const unique = [...new Set(ids)].slice(0, 24);

    if (unique.length === 0) {
      showToast("error", "No ingresaste IDs validos");
      return;
    }

    sendAction({ action: "screenshotBatch", targetIds: unique });
    showToast("info", `Solicitud enviada para ${unique.length} jugador(es)`);
  }, {
    placeholder: "12,15,20",
    defaultValue: defaultIds,
    submitText: "Capturar"
  });
}
function deleteMyVehicle() {
  sendAction({ action: "deleteVehicle", targetId: -1 });
}
function repairMyVehicle() {
  sendAction({ action: "repairVehicle", targetId: -1 });
}
function setMyVehiclePlate() {
  showInput("Placa del Vehiculo", "Ingresa la nueva placa", (plate) => {
    const clean = String(plate || "").trim();
    if (!clean) {
      showToast("error", "Placa invalida");
      return;
    }
    sendAction({ action: "setVehiclePlate", targetId: -1, plate: clean });
    showToast("success", "Placa enviada");
  }, {
    placeholder: "ADMIN01",
    defaultValue: "ADMIN01",
    submitText: "Aplicar",
  });
}
function toggleMyVehicleEngine() {
  sendAction({ action: "toggleVehicleEngine", targetId: -1 });
  showToast("info", "Motor alternado");
}
function toggleMyVehicleDoors() {
  sendAction({ action: "toggleVehicleDoors", targetId: -1, doorIndex: -1 });
  showToast("info", "Puertas alternadas");
}
function setMyVehicleFuel() {
  showInput("Combustible", "Ingresa nivel (0-100)", (fuel) => {
    const value = Math.max(0, Math.min(100, parseInt(fuel, 10) || 0));
    sendAction({ action: "setVehicleFuel", targetId: -1, fuelLevel: value });
    showToast("success", `Combustible: ${value}%`);
  }, {
    placeholder: "100",
    defaultValue: "100",
    submitText: "Aplicar",
  });
}
function fullServiceMyVehicle() {
  sendAction({ action: "repairVehicle", targetId: -1 });
  sendAction({ action: "cleanVehicle", targetId: -1 });
  sendAction({ action: "setVehicleFuel", targetId: -1, fuelLevel: 100 });
  showToast("success", "Servicio full aplicado");
}
function freezeMyVehicle() {
  const next = window.__lyxVehicleFrozen !== true;
  window.__lyxVehicleFrozen = next;
  sendAction({ action: "freezeVehicle", targetId: -1, enabled: next });
  document
    .getElementById("btnFreezeVehicle")
    ?.classList.toggle("active", next);
  showToast("info", next ? "Vehiculo congelado" : "Vehiculo descongelado");
}
function warpOutMyVehicle() {
  sendAction({ action: "warpOutOfVehicle", targetId: -1 });
  showToast("info", "Saliendo del vehiculo");
}
function spawnVehicle(m) {
  sendAction({ action: "spawnVehicle", model: m });
}

function quickSpawnWarpTune(model) {
  if (!model) return;
  sendAction({ action: "quickSpawnWarpTune", model });
  if (window.showToast) showToast("success", "Flujo rapido ejecutado");
}

// Custom vehicle spawn with toast notification
// Called from categories with model param, or from Vehicles page input without param
function spawnCustomVehicle(model) {
  // If no model passed, read from input field
  if (!model) {
    model = document.getElementById('customVehicleName')?.value?.trim();
  }
  if (!model) {
    if (window.showToast) showToast('error', 'Ingresa el nombre del vehiculo');
    return;
  }
  sendAction({ action: "spawnVehicle", model: model });
  if (window.Toast) {
    Toast.success('Vehiculo', `Spawneando: ${model}`);
  } else if (window.showToast) {
    showToast('success', `Spawneando ${model}...`);
  }
}

function refreshDependencyStatus(openData = {}) {
  const statusEl = document.getElementById("settingsGuardStatus");
  const profileEl = document.getElementById("runtimeProfileName");
  const hintEl = document.getElementById("dependencyHint");

  if (!statusEl || !profileEl || !hintEl) return;

  const guardAvailable = !!(
    openData?.integrations?.lyxGuard ||
    openData?.config?.dependencies?.lyxGuardAvailable
  );
  const runtimeProfile =
    openData?.config?.runtimeProfile || openData?.runtimeProfile || "default";

  profileEl.textContent = String(runtimeProfile);
  profileEl.className = "status-chip neutral";

  statusEl.textContent = guardAvailable ? "Activo" : "Inactivo";
  statusEl.className = `status-chip ${guardAvailable ? "online" : "offline"}`;
  hintEl.textContent = guardAvailable
    ? "Integracion basica disponible. Consultando estado detallado..."
    : "lyx-guard no esta activo. Algunas funciones sensibles quedan deshabilitadas.";

  fetch(`https://${GetParentResourceName()}/getDependencyStatus`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: "{}",
  })
    .then((r) => r.json())
    .then((resp) => {
      if (!resp || resp.success !== true) return;

      const guard = resp.guard || {};
      const panel = resp.panel || {};
      const hb = guard.heartbeat || {};
      const healthParts = [];

      const guardOnline = guard.available === true;
      statusEl.textContent = guardOnline ? "Activo" : "Inactivo";
      statusEl.className = `status-chip ${guardOnline ? "online" : "offline"}`;

      const profile = panel.runtimeProfile || runtimeProfile || "default";
      profileEl.textContent = String(profile);

      if (guardOnline) {
        if (guard.serverReady === true) {
          healthParts.push("guard listo");
        } else {
          healthParts.push("guard iniciando");
        }
        if (typeof hb.onlinePlayers === "number") {
          healthParts.push(`players ${hb.onlinePlayers}`);
        }
        if (typeof hb.staleHeartbeats === "number") {
          healthParts.push(`hb stale ${hb.staleHeartbeats}`);
        }
        if (typeof hb.maxAgeMs === "number") {
          healthParts.push(`maxAge ${Math.max(0, Math.floor(hb.maxAgeMs))}ms`);
        }
      } else {
        healthParts.push("integracion deshabilitada");
      }

      hintEl.textContent = healthParts.join(" | ");
    })
    .catch(() => {
      // Keep baseline text if detail check fails.
    });
}

// Filter custom vehicles by search (with debounce for performance)
let vehicleSearchTimeout = null;

function filterCustomVehicles() {
  // Debounce: wait 200ms before filtering
  clearTimeout(vehicleSearchTimeout);
  vehicleSearchTimeout = setTimeout(() => {
    performVehicleFilter();
  }, 200);
}

function performVehicleFilter() {
  const searchInput = document.getElementById('customVehicleSearch');
  const list = document.getElementById('customVehiclesList');
  if (!searchInput || !list) return;

  const query = searchInput.value.toLowerCase().trim();
  const items = list.querySelectorAll('.category-item');

  let visibleCount = 0;
  items.forEach(item => {
    const name = item.getAttribute('data-name') || '';
    const label = item.getAttribute('data-label') || '';

    if (name.includes(query) || label.includes(query) || query === '') {
      item.style.display = '';
      visibleCount++;
    } else {
      item.style.display = 'none';
    }
  });

  // Show "no results" message if needed
  let noResults = list.querySelector('.no-results');
  if (visibleCount === 0 && query !== '') {
    if (!noResults) {
      noResults = document.createElement('div');
      noResults.className = 'no-results';
      noResults.style.cssText = 'text-align: center; padding: 20px; color: rgba(168, 85, 247, 0.5);';
      noResults.innerHTML = '<i class="fas fa-search"></i> No se encontraron vehiculos';
      list.appendChild(noResults);
    }
    noResults.style.display = '';
  } else if (noResults) {
    noResults.style.display = 'none';
  }

  // Update visible count badge
  const badge = document.querySelector('.custom-vehicles-badge');
  if (badge && query !== '') {
    badge.textContent = visibleCount;
  }
}
// -----------------------------------------------------------------------------
// ADVANCED VEHICLE FUNCTIONS (v4.1)
// -----------------------------------------------------------------------------

// Clean current vehicle (remove dirt and visual damage)
function cleanVehicleSelf() {
  sendAction({ action: "cleanVehicle", targetId: -1 });
  if (window.Toast) Toast.success('Vehiculo', 'Limpiando...');
}

// Set vehicle color
function setVehicleColorSelf(primary, secondary) {
  sendAction({ action: "setVehicleColor", targetId: -1, primary: primary, secondary: secondary });
  if (window.Toast) Toast.success('Vehiculo', `Color cambiado: ${primary}/${secondary}`);
}

// Show vehicle color picker modal
function showVehicleColorPicker() {
  showInputModal(
    "Cambiar Color del Vehiculo",
    `<div class="form-group">
      <label>Color Primario (0-160)</label>
      <input type="number" id="inpVehPrimaryColor" value="0" min="0" max="160" class="input-full">
    </div>
    <div class="form-group">
      <label>Color Secundario (0-160)</label>
      <input type="number" id="inpVehSecondaryColor" value="0" min="0" max="160" class="input-full">
    </div>
    <button class="btn btn-primary btn-full" onclick="submitVehicleColor()">Aplicar Color</button>`
  );
}

function submitVehicleColor() {
  const primary = parseInt(document.getElementById('inpVehPrimaryColor').value) || 0;
  const secondary = parseInt(document.getElementById('inpVehSecondaryColor').value) || 0;
  setVehicleColorSelf(primary, secondary);
  closeInputModal();
}

// Tune vehicle to max
function tuneVehicleSelf() {
  sendAction({ action: "tuneVehicle", targetId: -1 });
  if (window.Toast) Toast.success('Vehiculo', 'Tuneando al maximo...');
}

// Toggle ghost mode for vehicle
let vehicleGhostActive = false;
function toggleVehicleGhost() {
  vehicleGhostActive = !vehicleGhostActive;
  sendAction({ action: "ghostVehicle", targetId: -1, enabled: vehicleGhostActive });
  if (window.Toast) Toast.success('Vehiculo', vehicleGhostActive ? 'Modo fantasma ACTIVADO' : 'Modo fantasma DESACTIVADO');
}

// Get vehicle info and show in UI
function getVehicleInfo() {
  sendAction({ action: "getVehicleInfo" });
}
// -----------------------------------------------------------------------------
// WEAPON & AMMO SYSTEM
// -----------------------------------------------------------------------------

let currentAmmoAmount = 250; // Default ammo amount

function setAmmoAmount(amount) {
  currentAmmoAmount = amount;
  document
    .querySelectorAll(".ammo-btn")
    .forEach((btn) => btn.classList.remove("active"));
  event.target.classList.add("active");
  const display = document.getElementById("currentAmmoDisplay");
  if (display) display.textContent = amount;
  showToast("info", `Municion establecida: ${amount}`);
}

function setCustomAmmo() {
  const input = document.getElementById("customAmmoAmount");
  const amount = parseInt(input.value);
  if (amount && amount > 0 && amount <= 9999) {
    currentAmmoAmount = amount;
    document
      .querySelectorAll(".ammo-btn")
      .forEach((btn) => btn.classList.remove("active"));
    const display = document.getElementById("currentAmmoDisplay");
    if (display) display.textContent = amount;
    showToast("success", `Municion personalizada: ${amount}`);
  } else {
    showToast("error", "Cantidad invalida (1-9999)");
  }
}

function giveWeaponSelf(w) {
  sendAction({
    action: "giveWeapon",
    targetId: -1,
    weapon: w,
    ammo: currentAmmoAmount,
  });
  showToast("success", `Arma: ${w} | Balas: ${currentAmmoAmount}`);
}

function giveAmmoOnlySelf() {
  const weapon = document.getElementById("ammoWeaponName")?.value?.trim();
  const amount =
    parseInt(document.getElementById("ammoOnlyAmount")?.value) || 250;
  if (!weapon) {
    showToast("error", "Ingresa el nombre del arma");
    return;
  }
  sendAction({
    action: "giveAmmo",
    targetId: -1,
    weapon: weapon,
    ammo: amount,
  });
  showToast("success", `Municion anadida: ${amount} balas para ${weapon}`);
}

function giveCustomWeaponSelf() {
  const weapon = document.getElementById("customWeaponName")?.value?.trim();
  const ammo =
    parseInt(document.getElementById("customWeaponAmmo")?.value) || 250;
  if (!weapon) {
    showToast("error", "Ingresa el nombre del arma");
    return;
  }
  sendAction({
    action: "giveWeapon",
    targetId: -1,
    weapon: weapon,
    ammo: ammo,
  });
  showToast("success", `Arma entregada: ${weapon} con ${ammo} balas`);
}

function teleportTo(x, y, z) {
  sendAction({ action: "teleportCoords", x: x, y: y, z: z });
}
function teleportCoords() {
  const x = parseFloat(document.getElementById("tpX").value),
    y = parseFloat(document.getElementById("tpY").value),
    z = parseFloat(document.getElementById("tpZ").value);
  if (!isNaN(x) && !isNaN(y) && !isNaN(z))
    sendAction({ action: "teleportCoords", x: x, y: y, z: z });
}
function spawnVehicleSelf() {
  const m = document.getElementById("spawnVehicleModel").value;
  if (m) sendAction({ action: "spawnVehicle", vehicle: m });
}
function setWeather() {
  sendAction({
    action: "setWeather",
    weather: document.getElementById("weatherSelect").value,
  });
}
function setTime() {
  const h = parseInt(document.getElementById("timeHour").value),
    m = parseInt(document.getElementById("timeMinute").value);
  sendAction({ action: "setTime", hour: h || 12, minute: m || 0 });
}
function giveItem() {
  sendAction({
    action: "giveItem",
    targetId: parseInt(document.getElementById("toolTargetPlayer").value),
    item: document.getElementById("toolItemName").value,
    count: document.getElementById("toolItemCount").value,
  });
}
function changeModel() {
  sendAction({
    action: "changeModel",
    targetId: parseInt(document.getElementById("modelTargetPlayer").value),
    model: document.getElementById("modelName").value,
  });
}
function addNote() {
  if (selectedPlayer)
    sendAction({
      action: "addNote",
      targetId: selectedPlayer.id,
      note: document.getElementById("newNoteText").value,
    });
}

// Economy
function ecoGive() {
  sendAction({
    action: "giveMoney",
    targetId: parseInt(document.getElementById("ecoTargetPlayer").value),
    account: document.getElementById("ecoAccount").value,
    amount: document.getElementById("ecoAmount").value,
  });
}
function ecoSet() {
  sendAction({
    action: "setMoney",
    targetId: parseInt(document.getElementById("ecoTargetPlayer").value),
    account: document.getElementById("ecoAccount").value,
    amount: document.getElementById("ecoAmount").value,
  });
}
function ecoRemove() {
  sendAction({
    action: "removeMoney",
    targetId: parseInt(document.getElementById("ecoTargetPlayer").value),
    account: document.getElementById("ecoAccount").value,
    amount: document.getElementById("ecoAmount").value,
  });
}
function ecoTransfer() {
  sendAction({
    action: "transferMoney",
    fromId: parseInt(document.getElementById("ecoFromPlayer").value),
    toId: parseInt(document.getElementById("ecoToPlayer").value),
    account: "bank",
    amount: document.getElementById("ecoTransferAmount").value,
  });
}

// Input modals
function openInputModal(title, html) {
  document.getElementById("inputModalTitle").textContent = title;
  document.getElementById("inputModalBody").innerHTML = html;
  document.getElementById("inputModal").classList.remove("hidden");
}

function openMoneyInput() {
  openInputModal(
    "Dar Dinero",
    `<select id="inpAccount" class="input-full"><option value="money">Efectivo</option><option value="bank">Banco</option><option value="black_money">Negro</option></select><input type="number" id="inpAmount" placeholder="Cantidad" class="input-full"><button class="btn btn-primary btn-full" onclick="submitMoney()">Dar</button>`
  );
}
function submitMoney() {
  sendAction({
    action: "giveMoney",
    targetId: selectedPlayer.id,
    account: document.getElementById("inpAccount").value,
    amount: document.getElementById("inpAmount").value,
  });
  closeInputModal();
}

function openWeaponInput() {
  openInputModal(
    "Dar Arma",
    `<input type="text" id="inpWeapon" placeholder="WEAPON_PISTOL" class="input-full"><input type="number" id="inpAmmo" value="250" placeholder="Cantidad de balas" class="input-full"><button class="btn btn-primary btn-full" onclick="submitWeapon()">Dar Arma</button>`
  );
}
function submitWeapon() {
  sendAction({
    action: "giveWeapon",
    targetId: selectedPlayer.id,
    weapon: document.getElementById("inpWeapon").value,
    ammo: document.getElementById("inpAmmo").value,
  });
  closeInputModal();
}

function openAmmoInput() {
  openInputModal(
    "Dar Municion",
    `<input type="text" id="inpAmmoWeapon" placeholder="WEAPON_PISTOL" class="input-full"><input type="number" id="inpAmmoCount" value="250" placeholder="Cantidad de balas" class="input-full"><button class="btn btn-primary btn-full" onclick="submitAmmo()"><i class="fas fa-bullseye"></i> Dar Balas</button>`
  );
}
function submitAmmo() {
  sendAction({
    action: "giveAmmo",
    targetId: selectedPlayer.id,
    weapon: document.getElementById("inpAmmoWeapon").value,
    ammo: document.getElementById("inpAmmoCount").value,
  });
  closeInputModal();
  showToast("success", "Municion enviada");
}

function openVehicleInput() {
  openInputModal(
    "Spawn Vehiculo",
    `<input type="text" id="inpVehicle" placeholder="adder" class="input-full"><button class="btn btn-primary btn-full" onclick="submitVehicle()">Spawn</button>`
  );
}
function submitVehicle() {
  sendAction({
    action: "spawnVehicle",
    targetId: selectedPlayer.id,
    vehicle: document.getElementById("inpVehicle").value,
  });
  closeInputModal();
}

function openJobInput() {
  openInputModal(
    "Asignar Trabajo",
    `<input type="text" id="inpJob" placeholder="police" class="input-full"><input type="number" id="inpGrade" value="0" class="input-full"><button class="btn btn-primary btn-full" onclick="submitJob()">Asignar</button>`
  );
}
function submitJob() {
  sendAction({
    action: "setJob",
    targetId: selectedPlayer.id,
    job: document.getElementById("inpJob").value,
    grade: document.getElementById("inpGrade").value,
  });
  closeInputModal();
}

function openItemInput() {
  openInputModal(
    "Dar Item",
    `<input type="text" id="inpItem" placeholder="bread" class="input-full"><input type="number" id="inpCount" value="1" class="input-full"><button class="btn btn-primary btn-full" onclick="submitItem()">Dar</button>`
  );
}
function submitItem() {
  sendAction({
    action: "giveItem",
    targetId: selectedPlayer.id,
    item: document.getElementById("inpItem").value,
    count: document.getElementById("inpCount").value,
  });
  closeInputModal();
}

function openArmorInput() {
  openInputModal(
    "Armadura",
    `<input type="number" id="inpArmor" value="100" min="0" max="100" class="input-full"><button class="btn btn-primary btn-full" onclick="submitArmor()">Establecer</button>`
  );
}
function submitArmor() {
  sendAction({
    action: "setArmor",
    targetId: selectedPlayer.id,
    amount: document.getElementById("inpArmor").value,
  });
  closeInputModal();
}

function openWarnInput() {
  openInputModal(
    "Advertir",
    `<input type="text" id="inpReason" placeholder="Razon" class="input-full"><button class="btn btn-primary btn-full" onclick="submitWarn()">Advertir</button>`
  );
}
function submitWarn() {
  sendAction({
    action: "warn",
    targetId: selectedPlayer.id,
    reason: document.getElementById("inpReason").value,
  });
  closeInputModal();
}

function openKickInput() {
  openInputModal(
    "Expulsar",
    `<input type="text" id="inpReason" placeholder="Razon" class="input-full"><button class="btn btn-danger btn-full" onclick="submitKick()">Expulsar</button>`
  );
}
function submitKick() {
  sendAction({
    action: "kick",
    targetId: selectedPlayer.id,
    reason: document.getElementById("inpReason").value,
  });
  closeInputModal();
  closeModal();
}

function openBanInput() {
  openInputModal(
    "Banear",
    `
        <input type="text" id="inpReason" placeholder="Razon" class="input-full">
        <select id="inpDuration" class="input-full" onchange="toggleCustomDuration()">
            <option value="short">1 Hora</option>
            <option value="medium">1 Dia</option>
            <option value="long">1 Semana</option>
            <option value="verylong">1 Mes</option>
            <option value="permanent">Permanente</option>
            <option value="custom">Personalizado...</option>
        </select>
        <div id="customDurationDiv" class="hidden" style="margin-top:8px">
            <input type="number" id="inpCustomHours" placeholder="Horas" class="input-full" min="1">
        </div>
        <button class="btn btn-danger btn-full" onclick="submitBan()">Banear</button>
    `
  );
}

function toggleCustomDuration() {
  const sel = document.getElementById("inpDuration");
  const div = document.getElementById("customDurationDiv");
  if (sel && div) {
    div.classList.toggle("hidden", sel.value !== "custom");
  }
}

function submitBan() {
  let duration = document.getElementById("inpDuration").value;
  if (duration === "custom") {
    const hours =
      parseInt(document.getElementById("inpCustomHours").value) || 1;
    duration = "custom:" + hours;
  }
  sendAction({
    action: "ban",
    targetId: selectedPlayer.id,
    reason: document.getElementById("inpReason").value,
    duration: duration,
  });
  closeInputModal();
  closeModal();
}

function openAnnounce() {
  openInputModal(
    "Anuncio Global",
    `<input type="text" id="inpMsg" placeholder="Mensaje" class="input-full"><button class="btn btn-primary btn-full" onclick="submitAnnounce()">Enviar</button>`
  );
}
function submitAnnounce() {
  sendAction({
    action: "announce",
    message: document.getElementById("inpMsg").value,
  });
  closeInputModal();
}

function openAdminChat() {
  openInputModal(
    "Admin Chat",
    `<input type="text" id="inpChatMsg" placeholder="Mensaje" class="input-full"><button class="btn btn-primary btn-full" onclick="submitAdminChat()">Enviar</button>`
  );
}
function submitAdminChat() {
  sendAction({
    action: "adminChat",
    message: document.getElementById("inpChatMsg").value,
  });
  closeInputModal();
}

// Load data functions
function loadDetections() {
  fetch(`https://${GetParentResourceName()}/getDetections`, {
    method: "POST",
    body: JSON.stringify({ limit: 100 }),
  })
    .then((r) => r.json())
    .then((d) => {
      document.getElementById("detectionsTableBody").innerHTML = d
        .map(
          (x) =>
            `<tr><td>${x.detection_date}</td><td>${esc(
              x.player_name || "N/A"
            )}</td><td><span class="badge badge-danger">${x.detection_type
            }</span></td><td><span class="badge badge-warning">${x.punishment || "N/A"
            }</span></td><td>${esc(x.details || "")}</td></tr>`
        )
        .join("");
    });
}

function loadBans() {
  fetch(`https://${GetParentResourceName()}/getBans`, {
    method: "POST",
    body: "{}",
  })
    .then((r) => r.json())
    .then((d) => {
      document.getElementById("bansTableBody").innerHTML = d
        .map((b) => {
          const identifier =
            b.identifier || b.license || b.steam || b.discord || "";
          const unbanToken = encodeURIComponent(String(identifier || ""));
          const expiresAt = b.permanent
            ? "Permanente"
            : b.unban_date || b.expire_date || "N/A";

          return `<tr><td>${esc(b.player_name || "N/A")}</td><td>${esc(
            b.reason || ""
          )}</td><td>${esc(b.banned_by || "System")}</td><td>${esc(
            b.ban_date || "N/A"
          )}</td><td>${esc(expiresAt)}</td><td>${b.active
            ? identifier
              ? `<button class="btn btn-sm btn-primary" onclick="unban('${unbanToken}')">Unban</button>`
              : '<span class="badge badge-warning">Sin ID</span>'
            : '<span class="badge badge-success">Inactivo</span>'
          }</td></tr>`;
        })
        .join("");
    });
}

function unban(encodedIdentifier) {
  const identifier = decodeURIComponent(String(encodedIdentifier || "")).trim();
  if (!identifier) {
    showToast("error", "Identifier invalido para desbanear");
    return;
  }
  sendAction({
    action: "unban",
    identifier: identifier,
    reason: "Unban desde panel",
  });
  setTimeout(loadBans, 500);
}

function openUnbanModal() {
  openInputModal(
    "Desbanear Jugador",
    `<div class="form-group">
      <label>Identifier (license:/steam:/discord:)</label>
      <input type="text" id="unbanIdentifierInput" placeholder="license:xxxxxxxx" class="input-full">
    </div>
    <div class="form-group">
      <label>Motivo</label>
      <input type="text" id="unbanReasonInput" value="Unban manual" class="input-full">
    </div>
    <button class="btn btn-primary btn-full" onclick="submitUnbanModal()">Desbanear</button>`
  );
}

function submitUnbanModal() {
  const identifier = (document.getElementById("unbanIdentifierInput")?.value || "").trim();
  const reason = (document.getElementById("unbanReasonInput")?.value || "Unban manual").trim();
  if (!identifier) {
    showToast("error", "Identifier requerido");
    return;
  }
  sendAction({
    action: "unban",
    identifier: identifier,
    reason: reason || "Unban manual",
  });
  closeInputModal();
  setTimeout(loadBans, 500);
}

// loadReports function moved to line ~699 with enhanced TP and chat features

function closeReport(id) {
  sendAction({ action: "closeReport", reportId: id, notes: "Cerrado" });
  setTimeout(loadReports, 500);
}

function loadLogs() {
  fetch(`https://${GetParentResourceName()}/getLogs`, {
    method: "POST",
    body: JSON.stringify({ limit: 100 }),
  })
    .then((r) => r.json())
    .then((d) => {
      document.getElementById("logsTableBody").innerHTML = d
        .map(
          (l) =>
            `<tr><td>${l.created_at}</td><td>${esc(
              l.admin_name
            )}</td><td><span class="badge badge-info">${l.action
            }</span></td><td>${esc(l.target_name || "N/A")}</td><td>${esc(
              l.details || ""
            )}</td></tr>`
        )
        .join("");
    });
}

// Navigation
document.querySelectorAll(".nav-item").forEach((item) => {
  item.onclick = function () {
    const page = this.dataset.page;
    document
      .querySelectorAll(".nav-item")
      .forEach((i) => i.classList.remove("active"));
    this.classList.add("active");
    document
      .querySelectorAll(".page")
      .forEach((p) => p.classList.remove("active"));
    document.getElementById("page-" + page)?.classList.add("active");
    if (page === "detections") loadDetections();
    if (page === "bans") loadBans();
    if (page === "reports") loadReports();
    if (page === "tickets" && typeof window.loadTickets === "function") window.loadTickets(true);
    if (page === "logs") loadLogs();
    if (page === "tools") {
      if (typeof loadSelfPresets === "function") loadSelfPresets();
      if (typeof loadVehicleBuilds === "function") loadVehicleBuilds();
      if (typeof loadVehicleFavorites === "function") loadVehicleFavorites();
      if (typeof loadVehicleSpawnHistory === "function") loadVehicleSpawnHistory();
    }
  };
});

// Helpers
function perm(p) {
  return adminPerms[p] === true;
}
function esc(s) {
  return s
    ? String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
    : "";
}
function fmt(n) {
  return n ? n.toLocaleString() : "0";
}
function GetParentResourceName() {
  return "lyx-panel";
}

function normalizeUiText(input) {
  if (input === null || input === undefined) return "";
  let text = String(input);

  // Remove common broken emoji/mojibake prefixes left from old encodings.
  text = text.replace(/^(?:\s*(?:[^\w<\[]+))+/u, "");

  return text.trim();
}

function toastSvgIcon(type) {
  const map = {
    success:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M9.5 16.2 5.8 12.5l1.4-1.4 2.3 2.3 7.3-7.3 1.4 1.4z"/></svg>',
    error:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M18.3 5.7 12 12l6.3 6.3-1.4 1.4L10.6 13.4 4.3 19.7l-1.4-1.4L9.2 12 2.9 5.7l1.4-1.4 6.3 6.3 6.3-6.3z"/></svg>',
    warning:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>',
    info:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M11 10h2v8h-2zm0-4h2v2h-2z"/><path fill="currentColor" d="M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16z"/></svg>',
  };
  return map[type] || map.info;
}
// -----------------------------------------------------------------------------
// CUSTOM MODAL SYSTEM
// -----------------------------------------------------------------------------

let confirmCallback = null;
let inputCallback = null;

function showConfirm(title, message, onConfirm, options = {}) {
  const modal = document.getElementById("confirmModal");
  const titleEl = document.getElementById("confirmModalTitle");
  const messageEl = document.getElementById("confirmModalMessage");
  const inputContainer = document.getElementById("confirmModalInput");
  const inputField = document.getElementById("confirmModalInputField");
  const inputLabel = document.getElementById("confirmModalInputLabel");
  const confirmBtn = document.getElementById("confirmModalBtn");

  if (!modal || !titleEl) return; // Fallback if elements don't exist

  const safeTitle = normalizeUiText(title);
  titleEl.innerHTML = `<i class="fas fa-${options.icon || "exclamation-triangle"
    }"></i> ${safeTitle}`;
  messageEl.textContent = message;

  if (options.requireInput) {
    inputContainer.classList.remove("hidden");
    inputLabel.textContent = options.inputLabel || "Ingresa valor:";
    inputField.placeholder = options.inputPlaceholder || "";
    inputField.value = "";
  } else {
    inputContainer.classList.add("hidden");
  }

  confirmBtn.className = `btn btn-${options.buttonType || "danger"}`;
  confirmBtn.innerHTML = `<i class="fas fa-${options.buttonIcon || "check"
    }"></i> ${options.buttonText || "Confirmar"}`;

  confirmCallback = onConfirm;
  modal.classList.remove("hidden");
}

function closeConfirmModal() {
  const modal = document.getElementById("confirmModal");
  if (modal) modal.classList.add("hidden");
  confirmCallback = null;
}

function executeConfirmAction() {
  const inputField = document.getElementById("confirmModalInputField");
  const inputContainer = document.getElementById("confirmModalInput");

  if (inputContainer && !inputContainer.classList.contains("hidden")) {
    if (confirmCallback) confirmCallback(inputField.value.trim());
  } else {
    if (confirmCallback) confirmCallback(true);
  }
  closeConfirmModal();
}

function showInput(title, message, onSubmit, options = {}) {
  const modal = document.getElementById("inputModal");
  const titleEl = document.getElementById("inputModalTitle");
  const messageEl = document.getElementById("inputModalMessage");
  const inputField = document.getElementById("inputModalField");

  if (!modal || !titleEl) return;

  const safeTitle = normalizeUiText(title);
  titleEl.innerHTML = `<i class="fas fa-${options.icon || "edit"
    }"></i> ${safeTitle}`;
  messageEl.textContent = message;
  inputField.placeholder = options.placeholder || "";
  inputField.value = options.defaultValue || "";

  inputCallback = onSubmit;
  modal.classList.remove("hidden");
  inputField.focus();
}

function closeInputModal() {
  const modal = document.getElementById("inputModal");
  if (modal) modal.classList.add("hidden");
  inputCallback = null;
}

function executeInputAction() {
  const value = document.getElementById("inputModalField").value.trim();
  if (inputCallback && value) {
    inputCallback(value);
  }
  closeInputModal();
}

// Toast notification system
function showToast(type, message) {
  const container = document.getElementById("toastContainer");
  if (!container) return;

  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  const safeMessage = normalizeUiText(message);
  toast.innerHTML = `<span class="emoji-svg toast-svg-icon">${toastSvgIcon(type)}</span><span>${esc(safeMessage)}</span>`;

  container.appendChild(toast);
  setTimeout(() => toast.classList.add("show"), 10);
  setTimeout(() => {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}
// -----------------------------------------------------------------------------
// CLEAR FUNCTIONS
// -----------------------------------------------------------------------------

function clearAllDetections() {
  showConfirm(
    "Limpiar Detecciones",
    "Estas seguro de que quieres eliminar TODAS las detecciones?",
    () => {
      sendAction({ action: "clearAllDetections" });
      setTimeout(loadDetections, 500);
      showToast("success", "Detecciones limpiadas");
    }
  );
}

function clearLogs() {
  showConfirm(
    "Limpiar Logs",
    "Estas seguro de que quieres eliminar todos los logs?",
    () => {
      sendAction({ action: "clearLogs" });
      setTimeout(loadLogs, 500);
      showToast("success", "Logs limpiados");
    }
  );
}
// -----------------------------------------------------------------------------
// THEME SYSTEM
// -----------------------------------------------------------------------------

const themes = {
  dark: { primary: "#4f8fff", bg: "#0a0a0f", secondary: "#1a1a2e" },
  purple: { primary: "#a855f7", bg: "#0f0a15", secondary: "#1a1028" },
  red: { primary: "#ef4444", bg: "#0f0a0a", secondary: "#1a1010" },
  green: { primary: "#22c55e", bg: "#0a0f0a", secondary: "#101a10" },
  cyan: { primary: "#06b6d4", bg: "#0a0f0f", secondary: "#101a1a" },
  gold: { primary: "#fbbf24", bg: "#0f0d0a", secondary: "#1a1510" },
  pink: { primary: "#ec4899", bg: "#0f0a0d", secondary: "#1a1018" },
  ocean: { primary: "#0ea5e9", bg: "#0a0d0f", secondary: "#10151a" },
};

function setTheme(themeId) {
  const theme = themes[themeId];
  if (!theme) return;

  // Update CSS variables - use correct variable names from style.css
  document.documentElement.style.setProperty("--accent-blue", theme.primary);
  document.documentElement.style.setProperty("--bg-dark", theme.bg);
  document.documentElement.style.setProperty(
    "--bg-card",
    `rgba(${hexToRgb(theme.secondary)}, 0.85)`
  );
  document.documentElement.style.setProperty(
    "--gradient-primary",
    `linear-gradient(135deg, ${theme.primary} 0%, ${adjustColor(
      theme.primary,
      -30
    )} 100%)`
  );

  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.theme === themeId);
  });

  localStorage.setItem("lyxpanel_theme", themeId);
  showToast("success", "Tema aplicado: " + themeId);
}

function applyCustomTheme() {
  const primary =
    document.getElementById("customThemePrimary")?.value || "#3da5ff";
  const bg =
    document.getElementById("customThemeBackground")?.value || "#0d1218";
  const secondary =
    document.getElementById("customThemeSecondary")?.value || "#1a1a2e";

  document.documentElement.style.setProperty("--accent-blue", primary);
  document.documentElement.style.setProperty("--bg-dark", bg);
  document.documentElement.style.setProperty(
    "--bg-card",
    `rgba(${hexToRgb(secondary)}, 0.85)`
  );
  document.documentElement.style.setProperty(
    "--gradient-primary",
    `linear-gradient(135deg, ${primary} 0%, ${adjustColor(primary, -30)} 100%)`
  );

  localStorage.setItem(
    "lyxpanel_custom_theme",
    JSON.stringify({ primary, bg, secondary })
  );
  localStorage.setItem("lyxpanel_theme", "custom");
  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.classList.remove("active");
  });
  showToast("success", "Tema custom aplicado");
}

function resetCustomTheme() {
  localStorage.removeItem("lyxpanel_custom_theme");
  const fallbackTheme =
    localStorage.getItem("lyxpanel_theme") === "custom"
      ? "dark"
      : localStorage.getItem("lyxpanel_theme") || "dark";
  setTheme(themes[fallbackTheme] ? fallbackTheme : "dark");
  showToast("info", "Tema custom reseteado");
}

// Helper function to convert hex to rgb
function hexToRgb(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result
    ? `${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(
      result[3],
      16
    )}`
    : "20, 20, 30";
}

// Helper function to adjust color brightness
function adjustColor(hex, percent) {
  const num = parseInt(hex.replace("#", ""), 16);
  const amt = Math.round(2.55 * percent);
  const R = Math.max(0, Math.min(255, (num >> 16) + amt));
  const G = Math.max(0, Math.min(255, ((num >> 8) & 0x00ff) + amt));
  const B = Math.max(0, Math.min(255, (num & 0x0000ff) + amt));
  return "#" + (0x1000000 + R * 0x10000 + G * 0x100 + B).toString(16).slice(1);
}

// Load saved theme
const savedTheme = localStorage.getItem("lyxpanel_theme");
if (savedTheme === "custom") {
  try {
    const customRaw = localStorage.getItem("lyxpanel_custom_theme");
    if (customRaw) {
      const custom = JSON.parse(customRaw);
      if (custom && custom.primary && custom.bg && custom.secondary) {
        document.documentElement.style.setProperty("--accent-blue", custom.primary);
        document.documentElement.style.setProperty("--bg-dark", custom.bg);
        document.documentElement.style.setProperty(
          "--bg-card",
          `rgba(${hexToRgb(custom.secondary)}, 0.85)`
        );
        document.documentElement.style.setProperty(
          "--gradient-primary",
          `linear-gradient(135deg, ${custom.primary} 0%, ${adjustColor(custom.primary, -30)} 100%)`
        );
      }
    }
  } catch (_) {
    setTheme("dark");
  }
} else if (savedTheme && themes[savedTheme]) {
  setTheme(savedTheme);
}
// -----------------------------------------------------------------------------
// TROLL ACTIONS
// -----------------------------------------------------------------------------

const trollActions = [
  { id: "troll_explode", label: "Explosion", icon: "bomb" },
  { id: "troll_fire", label: "Fuego", icon: "fire" },
  { id: "troll_launch", label: "Lanzar", icon: "rocket", input: { key: "force", label: "Fuerza de lanzamiento (1-200)", placeholder: "50", def: "50", min: 1, max: 200 } },
  { id: "troll_ragdoll", label: "Ragdoll", icon: "person-falling" },
  { id: "troll_drunk", label: "Borracho", icon: "wine-glass", input: { key: "duration", label: "Duracion (segundos)", placeholder: "30", def: "30", min: 1, max: 300 } },
  { id: "troll_drug", label: "Drogas", icon: "pills", input: { key: "duration", label: "Duracion (segundos)", placeholder: "20", def: "20", min: 1, max: 300 } },
  { id: "troll_blackscreen", label: "Pantalla", icon: "rectangle-xmark", input: { key: "duration", label: "Duracion (segundos)", placeholder: "10", def: "10", min: 1, max: 60 } },
  { id: "troll_scream", label: "Susto", icon: "ghost" },
  { id: "troll_randomtp", label: "TP Random", icon: "location-dot" },
  { id: "troll_strip", label: "Ropa", icon: "shirt" },
  { id: "troll_invert", label: "Invertir", icon: "arrows-rotate", input: { key: "duration", label: "Duracion (segundos)", placeholder: "15", def: "15", min: 1, max: 300 } },
  { id: "troll_chicken", label: "Pollo", icon: "kiwi-bird" },
  { id: "troll_dance", label: "Bailar", icon: "music" },
  // Nuevos trolls avanzados
  { id: "troll_invisible", label: "Invisible", icon: "eye-slash", input: { key: "duration", label: "Duracion (segundos)", placeholder: "30", def: "30", min: 1, max: 300 } },
  { id: "troll_spin", label: "Girar", icon: "rotate", input: { key: "duration", label: "Duracion (segundos)", placeholder: "15", def: "15", min: 1, max: 120 } },
  { id: "troll_shrink", label: "Enano", icon: "minimize", input: { key: "duration", label: "Duracion (segundos)", placeholder: "60", def: "60", min: 1, max: 600 } },
  { id: "troll_giant", label: "Gigante", icon: "maximize", input: { key: "duration", label: "Duracion (segundos)", placeholder: "30", def: "30", min: 1, max: 300 } },
  { id: "troll_clones", label: "Clones", icon: "users", input: { key: "count", label: "Cantidad de clones (1-10)", placeholder: "5", def: "5", min: 1, max: 10 } },
];

function buildTrollActions() {
  const grid = document.getElementById("trollActionsGrid");
  if (!grid) return;

  grid.innerHTML = trollActions
    .map(
      (t) =>
        `<button class="player-action-btn troll" onclick="trollAction('${t.id}')">
            <i class="fas fa-${t.icon}"></i>${t.label}
            ${t.input ? '<small class="muted">Configurable</small>' : ''}
        </button>`
    )
    .join("");
}

function trollAction(actionId) {
  const actionCfg = trollActions.find((t) => t.id === actionId);
  if (!selectedPlayer) return showToast("error", "No hay jugador seleccionado");

  const send = (extra = {}) => {
    sendAction({ action: actionId, targetId: selectedPlayer.id, ...extra });
    showToast("success", "Accion troll enviada");
  };

  if (actionCfg && actionCfg.input) {
    const i = actionCfg.input;
    showInput(
      actionCfg.label,
      i.label || "Valor",
      (raw) => {
        let val = parseInt(raw, 10);
        if (!Number.isFinite(val)) val = parseInt(i.def, 10) || 0;
        val = Math.max(i.min || 0, Math.min(i.max || 9999, val));
        send({ [i.key]: val });
      },
      {
        placeholder: i.placeholder || "",
        defaultValue: i.def || "",
        submitText: "Aplicar",
      }
    );
    return;
  }

  send();
}
// -----------------------------------------------------------------------------
// REPORTS WITH TP AND CHAT
// -----------------------------------------------------------------------------

function loadReports() {
  fetch(`https://${GetParentResourceName()}/getReports`, {
    method: "POST",
    body: "{}",
  })
    .then((r) => r.json())
    .then((d) => {
      document.getElementById("reportsTableBody").innerHTML = d
        .map((r) => {
          const pc =
            {
              low: "badge-success",
              medium: "badge-warning",
              high: "badge-danger",
              critical: "badge-purple",
            }[r.priority] || "badge-info";
          const sc =
            {
              open: "badge-warning",
              in_progress: "badge-info",
              closed: "badge-success",
            }[r.status] || "badge-info";
          return `<tr>
                <td>${r.id}</td>
                <td>${esc(r.reporter_name)}</td>
                <td>${esc(r.reason)}</td>
                <td><span class="badge ${pc}">${r.priority}</span></td>
                <td><span class="badge ${sc}">${r.status}</span></td>
                <td>
                    ${r.status !== "closed"
              ? `
                        <button class="btn btn-sm btn-info" onclick="tpToReporter('${r.reporter_id
              }')" title="TP al reporter"><i class="fas fa-location-arrow"></i></button>
                        <button class="btn btn-sm btn-secondary" onclick="openReportChat(${r.id
              }, '${esc(
                r.reporter_name
              )}')" title="Chat"><i class="fas fa-comment"></i></button>
                        <button class="btn btn-sm btn-success" onclick="closeReport(${r.id
              })"><i class="fas fa-check"></i></button>
                    `
              : ""
            }
                </td>
            </tr>`;
        })
        .join("");
    });
}

function tpToReporter(reporterId) {
  sendAction({ action: "tpToReporter", reporterId: reporterId });
  showToast("info", "Teleportando al reporter...");
}
// -----------------------------------------------------------------------------
// REPORT CHAT SYSTEM
// -----------------------------------------------------------------------------

let currentReportId = null;
let reportChatInterval = null;

function openReportChat(reportId, reporterName) {
  currentReportId = reportId;
  document.getElementById("reportChatId").textContent = reportId;
  document.getElementById("reportChatMessages").innerHTML =
    '<p class="chat-info">Cargando mensajes...</p>';
  document.getElementById("reportChatModal").classList.remove("hidden");
  loadReportMessages(reportId);

  // Auto-refresh messages every 3 seconds
  if (reportChatInterval) clearInterval(reportChatInterval);
  reportChatInterval = setInterval(() => {
    if (currentReportId) loadReportMessages(currentReportId);
  }, 3000);
}

function closeReportChat() {
  document.getElementById("reportChatModal").classList.add("hidden");
  currentReportId = null;
  if (reportChatInterval) {
    clearInterval(reportChatInterval);
    reportChatInterval = null;
  }
}

function loadReportMessages(reportId) {
  fetch(`https://${GetParentResourceName()}/getReportMessages`, {
    method: "POST",
    body: JSON.stringify({ reportId: reportId }),
  })
    .then((r) => r.json())
    .then((messages) => {
      const container = document.getElementById("reportChatMessages");
      if (!messages || messages.length === 0) {
        container.innerHTML = '<p class="chat-info">No hay mensajes aun</p>';
        return;
      }
      container.innerHTML = messages
        .map(
          (m) => `
            <div class="chat-message ${m.is_admin ? "admin" : "user"}">
                <strong>${esc(m.sender_name)}</strong>
                <p>${esc(m.message)}</p>
                <small>${m.created_at}</small>
            </div>
        `
        )
        .join("");
      container.scrollTop = container.scrollHeight;
    });
}

function sendReportMessage() {
  const input = document.getElementById("reportChatInput");
  const message = input.value.trim();
  if (!message || !currentReportId) return;

  sendAction({
    action: "sendReportMessage",
    reportId: currentReportId,
    message: message,
  });
  input.value = "";

  // Add message locally
  const container = document.getElementById("reportChatMessages");
  container.innerHTML += `
        <div class="chat-message admin">
            <strong>Tu (Admin)</strong>
            <p>${esc(message)}</p>
            <small>Ahora</small>
        </div>
    `;
  container.scrollTop = container.scrollHeight;
}

function sendReportChatMessage() {
  sendReportMessage();
}
// -----------------------------------------------------------------------------
// SOUNDS
// -----------------------------------------------------------------------------

let soundsEnabled = true;
let reportSoundsEnabled = true;

function toggleSounds() {
  soundsEnabled = document.getElementById("soundEnabled")?.checked ?? true;
  localStorage.setItem("lyxpanel_sounds", soundsEnabled);
}

function toggleReportSounds() {
  reportSoundsEnabled =
    document.getElementById("reportSoundEnabled")?.checked ?? true;
  localStorage.setItem("lyxpanel_report_sounds", reportSoundsEnabled);
}

// Load saved settings
soundsEnabled = localStorage.getItem("lyxpanel_sounds") !== "false";
reportSoundsEnabled =
  localStorage.getItem("lyxpanel_report_sounds") !== "false";
// -----------------------------------------------------------------------------
// WHITELIST & HISTORY
// -----------------------------------------------------------------------------

function loadWhitelist() {
  fetch(`https://${GetParentResourceName()}/getWhitelist`, {
    method: "POST",
    body: "{}",
  })
    .then((r) => r.json())
    .then((d) => {
      document.getElementById("whitelistTable").innerHTML = d
        .map(
          (w) =>
            `<tr>
                <td>${esc(w.name)}</td>
                <td>${esc(w.identifier)}</td>
                <td>${esc(w.added_by)}</td>
                <td>${w.created_at}</td>
                <td><button class="btn btn-sm btn-danger" onclick="removeWhitelist(${w.id
            })"><i class="fas fa-trash"></i></button></td>
            </tr>`
        )
        .join("");
    });
}

function openAddWhitelist() {
  showInput(
    "Anadir a Whitelist",
    "Ingresa el identifier del jugador (license:xxx)",
    (value) => {
      sendAction({ action: "addWhitelist", identifier: value });
      setTimeout(loadWhitelist, 500);
    },
    { placeholder: "license:xxxxxx" }
  );
}

function removeWhitelist(id) {
  showConfirm("Eliminar de Whitelist", "Estas seguro?", () => {
    sendAction({ action: "removeWhitelist", id: id });
    setTimeout(loadWhitelist, 500);
  });
}

function searchOfflinePlayers() {
  const query = document.getElementById("offlineSearch").value;
  if (!query) return;

  fetch(`https://${GetParentResourceName()}/searchPlayers`, {
    method: "POST",
    body: JSON.stringify({ query: query }),
  })
    .then((r) => r.json())
    .then((results) => {
      const container = document.getElementById("searchResults");
      if (!results || results.length === 0) {
        container.innerHTML = "<p>No se encontraron resultados</p>";
        return;
      }
      container.innerHTML = results
        .map(
          (p) => `
            <div class="search-result-card">
                <h4>${esc(p.name)}</h4>
                <div class="result-info">
                    <span><i class="fas fa-id-card"></i> ${esc(
            p.identifier?.substring(0, 20)
          )}...</span>
                    <span><i class="fas fa-briefcase"></i> ${esc(
            p.job || "N/A"
          )}</span>
                    <span><i class="fas fa-ban"></i> Bans: ${p.ban_count || 0
            }</span>
                    <span><i class="fas fa-exclamation-triangle"></i> Warns: ${p.warn_count || 0
            }</span>
                    <span><i class="fas fa-door-open"></i> Kicks: ${p.kick_count || 0
            }</span>
                </div>
            </div>
        `
        )
        .join("");
    });
}
// -----------------------------------------------------------------------------
// STATS UPDATE (with uptime)
// -----------------------------------------------------------------------------

function updateStats(s) {
  document.getElementById(
    "statPlayers"
  ).textContent = `${s.playersOnline}/${s.maxPlayers}`;
  document.getElementById("statDetections").textContent =
    s.detectionsToday || 0;
  document.getElementById("statBans").textContent = s.bansTotal || 0;
  document.getElementById("statReports").textContent = s.reportsOpen || 0;

  // Update uptime if available
  const uptimeEl = document.getElementById("statUptime");
  if (uptimeEl && s.uptime) {
    const hours = Math.floor(s.uptime / 3600);
    const minutes = Math.floor((s.uptime % 3600) / 60);
    uptimeEl.textContent = `${hours}h ${minutes}m`;
  }
}

// Update openPlayerModal to include troll tab
const originalOpenPlayerModal = openPlayerModal;
openPlayerModal = function (id) {
  originalOpenPlayerModal(id);
  setTimeout(buildTrollActions, 100);
};

console.log("[LyxPanel] v3.0 loaded with all features");
// -----------------------------------------------------------------------------
// PROFESSIONAL FEATURES v4.0
// Advanced UI helpers
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// TOAST NOTIFICATION SYSTEM
// -----------------------------------------------------------------------------

const Toast = {
  container: null,
  sounds: {
    success: null,
    error: null,
    warning: null,
    info: null
  },

  init() {
    this.container = document.getElementById('toastContainer');
    if (!this.container) {
      this.container = document.createElement('div');
      this.container.id = 'toastContainer';
      this.container.className = 'toast-container';
      document.body.appendChild(this.container);
    }
  },

  show(type, title, message, duration = 5000) {
    this.init();

    const icons = {
      success: 'fas fa-check',
      error: 'fas fa-times',
      warning: 'fas fa-exclamation',
      info: 'fas fa-info'
    };

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
      <div class="toast-icon"><i class="${icons[type] || icons.info}"></i></div>
      <div class="toast-content">
        <div class="toast-title">${title}</div>
        <div class="toast-message">${message}</div>
      </div>
      <button class="toast-close" onclick="this.parentElement.remove()">
        <i class="fas fa-times"></i>
      </button>
      <div class="toast-progress"></div>
    `;

    this.container.appendChild(toast);

    // Play sound if enabled
    this.playSound(type);

    // Auto remove
    setTimeout(() => {
      toast.classList.add('removing');
      setTimeout(() => toast.remove(), 300);
    }, duration);

    return toast;
  },

  success(title, message) { return this.show('success', title, message); },
  error(title, message) { return this.show('error', title, message); },
  warning(title, message) { return this.show('warning', title, message); },
  info(title, message) { return this.show('info', title, message); },

  playSound(type) {
    // Sound effects can be added here if desired
    // Currently disabled to avoid requiring audio files
  }
};

// Make Toast globally available
window.Toast = Toast;
// -----------------------------------------------------------------------------
// COMMAND PALETTE SYSTEM
// -----------------------------------------------------------------------------

const CommandPalette = {
  isOpen: false,
  commands: [],
  selectedIndex: 0,

  init() {
    this.overlay = document.getElementById('commandPalette');
    this.input = document.getElementById('commandInput');
    this.results = document.getElementById('commandResults');

    if (!this.overlay || !this.input) return;

    // Register default commands
    this.registerDefaultCommands();

    // Input events
    this.input.addEventListener('input', () => this.filter());
    this.input.addEventListener('keydown', (e) => this.handleKeydown(e));

    // Close on overlay click
    this.overlay.addEventListener('click', (e) => {
      if (e.target === this.overlay) this.close();
    });
  },

  registerDefaultCommands() {
    this.commands = [
      { id: 'goto-dashboard', icon: 'fas fa-chart-pie', title: 'Ir a Dashboard', desc: 'Ver estadisticas', shortcut: '1', action: () => this.navigateTo('dashboard') },
      { id: 'goto-players', icon: 'fas fa-users', title: 'Ir a Jugadores', desc: 'Gestionar jugadores', shortcut: '2', action: () => this.navigateTo('players') },
      { id: 'goto-vehicles', icon: 'fas fa-car', title: 'Ir a Vehiculos', desc: 'Spawneo de vehiculos', shortcut: '3', action: () => this.navigateTo('vehicles') },
      { id: 'goto-weapons', icon: 'fas fa-gun', title: 'Ir a Armas', desc: 'Gestionar armamento', shortcut: '4', action: () => this.navigateTo('weapons') },
      { id: 'goto-economy', icon: 'fas fa-coins', title: 'Ir a Economia', desc: 'Gestionar dinero', shortcut: '5', action: () => this.navigateTo('economy') },
      { id: 'goto-bans', icon: 'fas fa-ban', title: 'Ir a Bans', desc: 'Baneos activos', shortcut: '7', action: () => this.navigateTo('bans') },
      { id: 'goto-tickets', icon: 'fas fa-headset', title: 'Ir a Tickets', desc: 'Soporte / tickets', shortcut: '8', action: () => this.navigateTo('tickets') },
      { id: 'toggle-godmode', icon: 'fas fa-heart', title: 'Toggle Godmode', desc: 'Hacerte invencible', shortcut: 'G', action: () => { toggleGodmode(); this.close(); } },
      { id: 'toggle-noclip', icon: 'fas fa-ghost', title: 'Toggle Noclip', desc: 'Atravesar paredes', shortcut: 'V', action: () => { toggleNoclip(); this.close(); } },
      { id: 'toggle-invisible', icon: 'fas fa-eye-slash', title: 'Toggle Invisible', desc: 'Hacerte invisible', shortcut: 'I', action: () => { toggleInvisible(); this.close(); } },
      { id: 'heal-self', icon: 'fas fa-medkit', title: 'Curarse', desc: 'Recuperar vida completa', shortcut: 'H', action: () => { healSelf(); this.close(); Toast.success('Curado', 'Vida restaurada'); } },
      { id: 'refresh-data', icon: 'fas fa-sync-alt', title: 'Actualizar datos', desc: 'Refrescar info', shortcut: 'R', action: () => { refreshData(); this.close(); Toast.info('Actualizado', 'Datos refrescados'); } },
      { id: 'teleport-marker', icon: 'fas fa-map-marker-alt', title: 'TP a Marcador', desc: 'Teletransportarse al marcador', shortcut: 'T', action: () => { teleportMarker(); this.close(); } },
      { id: 'delete-vehicle', icon: 'fas fa-car-crash', title: 'Eliminar Vehiculo', desc: 'Borrar vehiculo actual', action: () => { deleteMyVehicle(); this.close(); } },
      { id: 'repair-vehicle', icon: 'fas fa-wrench', title: 'Reparar Vehiculo', desc: 'Arreglar vehiculo actual', action: () => { repairMyVehicle(); this.close(); Toast.success('Reparado', 'Vehiculo reparado'); } },
      { id: 'close-panel', icon: 'fas fa-times', title: 'Cerrar Panel', desc: 'Cerrar LyxPanel', shortcut: 'ESC', action: () => { this.close(); closePanel(); } },
    ];
  },

  navigateTo(page) {
    document.querySelectorAll('.nav-item').forEach(item => {
      item.classList.remove('active');
      if (item.dataset.page === page) item.classList.add('active');
    });
    document.querySelectorAll('.page').forEach(p => {
      p.classList.remove('active');
      if (p.id === `page-${page}`) p.classList.add('active');
    });
    if (page === "detections") loadDetections();
    if (page === "bans") loadBans();
    if (page === "reports") loadReports();
    if (page === "tickets" && typeof window.loadTickets === "function") window.loadTickets(true);
    if (page === "logs") loadLogs();
    if (page === "tools") {
      if (typeof loadSelfPresets === "function") loadSelfPresets();
      if (typeof loadVehicleBuilds === "function") loadVehicleBuilds();
      if (typeof loadVehicleFavorites === "function") loadVehicleFavorites();
      if (typeof loadVehicleSpawnHistory === "function") loadVehicleSpawnHistory();
    }
    this.close();
  },

  open() {
    if (!this.overlay) this.init();
    if (!this.overlay) return;

    this.isOpen = true;
    this.overlay.classList.add('active');
    this.input.value = '';
    this.input.focus();
    this.filter();
    this.selectedIndex = 0;
    this.updateSelection();
  },

  close() {
    if (!this.overlay) return;
    this.isOpen = false;
    this.overlay.classList.remove('active');
  },

  toggle() {
    this.isOpen ? this.close() : this.open();
  },

  filter() {
    const query = this.input.value.toLowerCase().trim();
    const filtered = query ? this.commands.filter(cmd =>
      cmd.title.toLowerCase().includes(query) ||
      cmd.desc.toLowerCase().includes(query)
    ) : this.commands;

    this.renderResults(filtered);
    this.selectedIndex = 0;
    this.updateSelection();
  },

  renderResults(commands) {
    if (!this.results) return;

    this.results.innerHTML = commands.map((cmd, i) => `
      <div class="command-item ${i === 0 ? 'selected' : ''}" data-index="${i}" data-action="${cmd.id}">
        <i class="${cmd.icon}"></i>
        <div class="command-item-text">
          <div class="command-item-title">${cmd.title}</div>
          <div class="command-item-desc">${cmd.desc}</div>
        </div>
        ${cmd.shortcut ? `<div class="command-item-shortcut"><kbd>${cmd.shortcut}</kbd></div>` : ''}
      </div>
    `).join('');

    // Add click handlers
    this.results.querySelectorAll('.command-item').forEach(item => {
      item.addEventListener('click', () => {
        const index = parseInt(item.dataset.index);
        const cmd = commands[index];
        if (cmd && cmd.action) cmd.action();
      });
    });

    this.currentResults = commands;
  },

  updateSelection() {
    if (!this.results) return;
    const items = this.results.querySelectorAll('.command-item');
    items.forEach((item, i) => {
      item.classList.toggle('selected', i === this.selectedIndex);
    });

    // Scroll into view
    const selected = items[this.selectedIndex];
    if (selected) selected.scrollIntoView({ block: 'nearest' });
  },

  handleKeydown(e) {
    const items = this.results?.querySelectorAll('.command-item');
    if (!items) return;

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1);
        this.updateSelection();
        break;
      case 'ArrowUp':
        e.preventDefault();
        this.selectedIndex = Math.max(this.selectedIndex - 1, 0);
        this.updateSelection();
        break;
      case 'Enter':
        e.preventDefault();
        if (this.currentResults && this.currentResults[this.selectedIndex]) {
          this.currentResults[this.selectedIndex].action();
        }
        break;
      case 'Escape':
        e.preventDefault();
        this.close();
        break;
    }
  }
};

// Initialize Command Palette
window.CommandPalette = CommandPalette;
// -----------------------------------------------------------------------------
// KEYBOARD SHORTCUTS SYSTEM
// -----------------------------------------------------------------------------

const KeyboardShortcuts = {
  shortcuts: {},
  enabled: true,

  init() {
    document.addEventListener('keydown', (e) => this.handleKey(e));
    this.registerDefaults();
  },

  registerDefaults() {
    // Command palette
    this.register('Ctrl+K', () => CommandPalette.toggle());
    this.register('Ctrl+P', () => CommandPalette.toggle());

    // Page navigation (number keys)
    const pages = ['dashboard', 'players', 'vehicles', 'weapons', 'economy', 'world', 'reports', 'bans', 'detections'];
    pages.forEach((page, i) => {
      this.register(`${i + 1}`, () => {
        if (!this.isInputFocused()) {
          CommandPalette.navigateTo(page);
        }
      });
    });

    // Quick actions
    this.register('r', () => { if (!this.isInputFocused()) { refreshData(); Toast.info('Actualizado', 'Datos refrescados'); } });
    this.register('g', () => { if (!this.isInputFocused()) toggleGodmode(); });
    this.register('h', () => { if (!this.isInputFocused()) { healSelf(); Toast.success('Curado', 'Vida restaurada'); } });
    this.register('t', () => { if (!this.isInputFocused()) teleportMarker(); });
  },

  register(combo, callback) {
    this.shortcuts[combo.toLowerCase()] = callback;
  },

  isInputFocused() {
    const active = document.activeElement;
    // v4.2 FIX: Include SELECT elements and check contentEditable properly
    if (!active) return false;
    const tag = active.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || active.contentEditable === 'true';
  },

  handleKey(e) {
    if (!this.enabled) return;
    
    // v4.2 FIX: CRITICAL - Skip ALL shortcuts when input is focused
    // This prevents letters/numbers from being captured when typing
    if (this.isInputFocused()) {
      return; // Let the input receive the keypress normally
    }

    // Build combo string
    let combo = '';
    if (e.ctrlKey) combo += 'ctrl+';
    if (e.altKey) combo += 'alt+';
    if (e.shiftKey) combo += 'shift+';
    combo += e.key.toLowerCase();

    // Check for match
    const handler = this.shortcuts[combo];
    if (handler) {
      e.preventDefault();
      handler();
    }
  }
};

// Initialize shortcuts
KeyboardShortcuts.init();
// -----------------------------------------------------------------------------
// ENHANCED ESCAPE HANDLER
// -----------------------------------------------------------------------------

// Override the escape handler to include command palette
const originalEscapeHandler = document.onkeydown;
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    // Priority: Command Palette > Modals > Panel
    if (CommandPalette.isOpen) {
      CommandPalette.close();
      e.stopPropagation();
      return;
    }
  }
}, true);
// -----------------------------------------------------------------------------
// AUTO-REFRESH SYSTEM
// -----------------------------------------------------------------------------

const AutoRefresh = {
  interval: null,
  delay: 30000, // 30 seconds

  start() {
    this.stop();
    this.interval = setInterval(() => {
      if (!document.hidden) {
        refreshData();
      }
    }, this.delay);
  },

  stop() {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
  },

  setDelay(ms) {
    this.delay = ms;
    if (this.interval) this.start();
  }
};

// Start auto-refresh when panel opens
const originalOpenPanel = window.openPanel;
window.openPanel = function (data) {
  if (originalOpenPanel) originalOpenPanel(data);
  AutoRefresh.start();
  CommandPalette.init();
  Toast.info('Panel Abierto', 'LyxPanel v4.0 cargado');
};

// Stop auto-refresh when panel closes
const originalClosePanel = window.closePanel;
window.closePanel = function () {
  AutoRefresh.stop();
  if (originalClosePanel) originalClosePanel();
};
// -----------------------------------------------------------------------------
// ACTIVITY FEED
// -----------------------------------------------------------------------------

const ActivityFeed = {
  activities: [],
  maxItems: 50,

  add(type, text) {
    const activity = {
      type,
      text,
      time: new Date()
    };
    this.activities.unshift(activity);
    if (this.activities.length > this.maxItems) {
      this.activities.pop();
    }
    this.render();
  },

  render() {
    const container = document.getElementById('activityList');
    if (!container) return;

    container.innerHTML = this.activities.map(act => {
      const icons = {
        join: 'fas fa-sign-in-alt',
        leave: 'fas fa-sign-out-alt',
        detection: 'fas fa-shield-alt',
        ban: 'fas fa-ban',
        action: 'fas fa-bolt'
      };

      const timeAgo = this.getTimeAgo(act.time);

      return `
        <div class="activity-item">
          <div class="activity-icon ${act.type}">
            <i class="${icons[act.type] || icons.action}"></i>
          </div>
          <div class="activity-content">
            <div class="activity-text">${act.text}</div>
            <div class="activity-time">${timeAgo}</div>
          </div>
        </div>
      `;
    }).join('');
  },

  getTimeAgo(date) {
    const seconds = Math.floor((new Date() - date) / 1000);
    if (seconds < 60) return 'Ahora';
    if (seconds < 3600) return `Hace ${Math.floor(seconds / 60)}m`;
    if (seconds < 86400) return `Hace ${Math.floor(seconds / 3600)}h`;
    return `Hace ${Math.floor(seconds / 86400)}d`;
  }
};

window.ActivityFeed = ActivityFeed;
// -----------------------------------------------------------------------------
// ENHANCED ACTIONS WITH TOAST FEEDBACK
// -----------------------------------------------------------------------------

// Wrap common actions with toast feedback
const originalToggleNoclip = window.toggleNoclip;
window.toggleNoclip = function () {
  if (originalToggleNoclip) originalToggleNoclip();
  Toast.info('Noclip', noclipActive ? 'Activado' : 'Desactivado');
};

const originalToggleGodmode = window.toggleGodmode;
window.toggleGodmode = function () {
  if (originalToggleGodmode) originalToggleGodmode();
  Toast.info('Godmode', godmodeActive ? 'Activado' : 'Desactivado');
};

const originalToggleInvisible = window.toggleInvisible;
window.toggleInvisible = function () {
  if (originalToggleInvisible) originalToggleInvisible();
  Toast.info('Invisible', invisibleActive ? 'Activado' : 'Desactivado');
};
// -----------------------------------------------------------------------------
// NUMBER ANIMATION
// -----------------------------------------------------------------------------

function animateNumber(element, newValue) {
  if (!element) return;
  const current = parseInt(element.textContent) || 0;
  if (current === newValue) return;

  element.classList.add('updating');
  setTimeout(() => element.classList.remove('updating'), 300);

  const duration = 500;
  const start = performance.now();

  function update(now) {
    const progress = Math.min((now - start) / duration, 1);
    const value = Math.floor(current + (newValue - current) * progress);
    element.textContent = value;

    if (progress < 1) {
      requestAnimationFrame(update);
    }
  }

  requestAnimationFrame(update);
}
// -----------------------------------------------------------------------------
// CONFIRMATION DIALOG ENHANCEMENT
// -----------------------------------------------------------------------------

window.showConfirmAsync = function (title, message) {
  return new Promise((resolve) => {
    showConfirm(title, message, () => resolve(true));
    // Add cancel handler
    const modal = document.getElementById('confirmModal');
    if (modal) {
      const cancelBtn = modal.querySelector('.btn-secondary');
      if (cancelBtn) {
        cancelBtn.onclick = () => {
          modal.classList.add('hidden');
          resolve(false);
        };
      }
    }
  });
};
// -----------------------------------------------------------------------------
// v4.2 - NEW FEATURE FUNCTIONS
// -----------------------------------------------------------------------------

// Admin Jail - opens input for duration
function openAdminJailInput() {
  showInput("Admin Jail", "Duracion (segundos)", (duration) => {
    sendAction({ action: "adminJail", targetId: selectedPlayer.id, duration: parseInt(duration) || 300 });
    showToast("success", "Jugador enviado a Admin Jail");
    closeModal();
  });
}

// Wipe Player Data - triple verification (high risk)
function confirmWipePlayer() {
  // Step 1: Create custom modal with text input
  const modal = document.createElement('div');
  modal.id = 'wipeVerificationModal';
  modal.className = 'modal-overlay';
  modal.innerHTML = `
    <div class="modal-content danger-modal">
      <div class="modal-header danger">
        <h2>ACCION IRREVERSIBLE</h2>
        <p>Esta accion <b>ELIMINARA PERMANENTEMENTE</b> todos los datos del jugador:</p>
        <p class="player-name">${selectedPlayer ? selectedPlayer.name : 'Desconocido'}</p>
      </div>
      <div class="modal-body">
        <div class="verification-step step-1">
          <label>Paso 1: Escribe <b>CONFIRMO</b> para continuar:</label>
          <input type="text" id="wipeConfirmInput" placeholder="Escribe CONFIRMO" autocomplete="off" style="text-transform: uppercase;">
          <p class="hint">Debe coincidir exactamente</p>
        </div>
        <div class="verification-step step-2" style="display:none;">
          <label>Paso 2: Esperando confirmacion...</label>
          <div class="countdown-bar"><div class="countdown-progress"></div></div>
          <p class="hint">Espera 3 segundos para confirmar que no fue accidental</p>
        </div>
        <div class="verification-step step-3" style="display:none;">
          <label>Paso 3: Confirmacion final</label>
          <button class="btn btn-danger btn-lg" id="finalWipeBtn">
            <i class="fas fa-skull-crossbones"></i> ELIMINAR DATOS PERMANENTEMENTE
          </button>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-secondary" onclick="closeWipeModal()">Cancelar</button>
      </div>
    </div>
  `;

  document.body.appendChild(modal);

  // Focus on input
  setTimeout(() => {
    const input = document.getElementById('wipeConfirmInput');
    if (input) input.focus();
  }, 100);

  // Step 1: Listen for correct text
  const input = document.getElementById('wipeConfirmInput');
  input.addEventListener('input', function () {
    if (this.value.toUpperCase() === 'CONFIRMO') {
      // Move to step 2
      document.querySelector('.step-1').style.display = 'none';
      document.querySelector('.step-2').style.display = 'block';

      // Countdown animation
      const progress = document.querySelector('.countdown-progress');
      progress.style.width = '100%';

      let countdown = 3;
      const interval = setInterval(() => {
        countdown--;
        progress.style.width = (countdown / 3 * 100) + '%';

        if (countdown <= 0) {
          clearInterval(interval);
          // Move to step 3
          document.querySelector('.step-2').style.display = 'none';
          document.querySelector('.step-3').style.display = 'block';

          // Final button
          document.getElementById('finalWipeBtn').addEventListener('click', function () {
            sendAction({ action: "wipePlayer", targetId: selectedPlayer.id });
            showToast("warning", "Datos del jugador eliminados permanentemente");
            closeWipeModal();
            closeModal();
          });
        }
      }, 1000);
    }
  });
}

function closeWipeModal() {
  const modal = document.getElementById('wipeVerificationModal');
  if (modal) modal.remove();
}

// Revive All Players
function reviveAllPlayers() {
  showConfirm("Revivir a Todos", "Revivir a todos los jugadores del servidor?", () => {
    sendAction({ action: "reviveAll" });
    showToast("success", "Todos los jugadores revividos");
  });
}

// Global Announcement
function openAnnouncementInput() {
  showInput("Anuncio Global", "Mensaje para todos", (message) => {
    sendAction({ action: "announcement", message: message });
    showToast("success", "Anuncio enviado");
  });
}

// Clear Area
function openClearAreaInput() {
  showInput("Limpiar Area", "Radio en metros (ej: 100)", (radius) => {
    sendAction({ action: "clearArea", radius: parseInt(radius) || 100 });
    showToast("success", "Area limpiada");
  });
}

// Give Money to All
function openGiveMoneyAllInput() {
  showInput("Dar Dinero a Todos", "Cantidad", (amount) => {
    sendAction({ action: "giveMoneyAll", amount: parseInt(amount) || 1000 });
    showToast("success", "Dinero dado a todos los jugadores");
  });
}
// -----------------------------------------------------------------------------
// v4.3 ELITE FEATURES
// -----------------------------------------------------------------------------

// Freecam Toggle
function toggleFreecam() {
  sendNUI({ action: "toggleFreecam" }, (resp) => {
    const btn = document.getElementById("btnFreecam");
    if (resp && resp.active) {
      btn.classList.add("active");
      showToast("info", "Freecam activado (ESC para salir)");
      closePanel(); // Close panel when entering freecam
    } else {
      btn.classList.remove("active");
      showToast("info", "Freecam desactivado");
    }
  });
}

// Zone Cleanup Modal
function openZoneCleanup() {
  const modal = document.createElement("div");
  modal.id = "zoneCleanupModal";
  modal.className = "modal";
  modal.innerHTML = `
    <div class="modal-content modal-small">
      <div class="modal-header">
        <h2><i class="fas fa-broom"></i> Limpiar Zona</h2>
        <button class="modal-close" onclick="closeZoneModal()">&times;</button>
      </div>
      <div class="modal-body">
        <div style="margin-bottom: 15px;">
          <label>Radio (metros):</label>
          <input type="number" id="cleanupRadius" value="100" min="10" max="500" class="input-full">
        </div>
        <div style="margin-bottom: 15px;">
          <label class="toggle-label">
            <input type="checkbox" id="cleanVehicles" checked> Eliminar Vehiculos
          </label>
        </div>
        <div style="margin-bottom: 15px;">
          <label class="toggle-label">
            <input type="checkbox" id="cleanPeds"> Eliminar NPCs
          </label>
        </div>
        <div style="margin-bottom: 15px;">
          <label class="toggle-label">
            <input type="checkbox" id="cleanObjects"> Eliminar Objetos
          </label>
        </div>
        <button class="btn btn-danger btn-full" onclick="executeZoneCleanup()">
          <i class="fas fa-trash"></i> Limpiar Zona
        </button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
}

function closeZoneModal() {
  const modal = document.getElementById("zoneCleanupModal");
  if (modal) modal.remove();
}

function executeZoneCleanup() {
  const radius = parseInt(document.getElementById("cleanupRadius").value) || 100;
  const vehicles = document.getElementById("cleanVehicles").checked;
  const peds = document.getElementById("cleanPeds").checked;
  const objects = document.getElementById("cleanObjects").checked;

  sendNUI({ action: "cleanupZone", radius, vehicles, peds, objects }, (stats) => {
    showToast("success", `Eliminados: ${stats.vehicles} vehiculos, ${stats.peds} NPCs, ${stats.objects} objetos`);
    closeZoneModal();
  });
}

// Warps Manager Modal
function openWarpsManager() {
  sendNUI({ action: "getWarps" }, (warps) => {
    let warpsList = "";
    if (warps && warps.length > 0) {
      warpsList = warps.map(w => `
        <div class="warp-item" style="display:flex; justify-content:space-between; padding:8px; background:rgba(0,0,0,0.3); border-radius:6px; margin-bottom:6px;">
          <span>${esc(w.name)}</span>
          <div>
            <button class="btn btn-sm btn-primary" onclick="teleportToWarp('${esc(w.name)}')">
              <i class="fas fa-location-arrow"></i>
            </button>
            <button class="btn btn-sm btn-danger" onclick="deleteWarp('${esc(w.name)}')">
              <i class="fas fa-trash"></i>
            </button>
          </div>
        </div>
      `).join("");
    } else {
      warpsList = "<p style='color:var(--text-muted);text-align:center;'>No hay warps guardados</p>";
    }

    const modal = document.createElement("div");
    modal.id = "warpsModal";
    modal.className = "modal";
    modal.innerHTML = `
      <div class="modal-content">
        <div class="modal-header">
          <h2><i class="fas fa-bookmark"></i> Warps Guardados</h2>
          <button class="modal-close" onclick="closeWarpsModal()">&times;</button>
        </div>
        <div class="modal-body">
          <div style="margin-bottom: 15px;">
            <div style="display:flex;gap:10px;">
              <input type="text" id="newWarpName" placeholder="Nombre del warp" class="input-full" style="flex:1;">
              <button class="btn btn-primary" onclick="saveCurrentWarp()">
                <i class="fas fa-plus"></i> Guardar Posicion
              </button>
            </div>
          </div>
          <div style="max-height:300px;overflow-y:auto;">
            ${warpsList}
          </div>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
  });
}

function closeWarpsModal() {
  const modal = document.getElementById("warpsModal");
  if (modal) modal.remove();
}

function saveCurrentWarp() {
  const name = document.getElementById("newWarpName").value.trim();
  if (!name) {
    showToast("error", "Ingresa un nombre para el warp");
    return;
  }
  sendNUI({ action: "addWarp", name }, (resp) => {
    if (resp && resp.success) {
      showToast("success", `Warp "${name}" guardado`);
      closeWarpsModal();
      openWarpsManager(); // Refresh list
    }
  });
}

function teleportToWarp(name) {
  sendNUI({ action: "teleportToWarp", name }, (resp) => {
    if (resp && resp.success) {
      showToast("success", `Teleportado a "${name}"`);
      closeWarpsModal();
    }
  });
}

function deleteWarp(name) {
  sendNUI({ action: "deleteWarp", name }, (resp) => {
    if (resp && resp.success) {
      showToast("success", `Warp "${name}" eliminado`);
      closeWarpsModal();
      openWarpsManager(); // Refresh list
    }
  });
}

// Area Scan
function scanArea() {
  showInput("Escanear Area", "Radio en metros (ej: 100)", (radius) => {
    sendNUI({ action: "scanArea", radius: parseInt(radius) || 100 }, (stats) => {
      showConfirm("Resultado del Escaneo",
        `En un radio de ${radius}m:\n\n` +
        `Vehiculos: ${stats.vehicles}\n` +
        `Jugadores: ${stats.players}\n` +
        `NPCs: ${stats.peds}`,
        () => { }
      );
    });
  });
}

// Spectate Nearest Player
function spectateNearest() {
  sendNUI({ action: "spectateNearest" }, (resp) => {
    if (resp && resp.success) {
      showToast("success", `Espectando jugador mas cercano (${Math.round(resp.distance)}m)`);
    } else {
      showToast("warning", "No hay jugadores cerca para espectar");
    }
  });
}
// -----------------------------------------------------------------------------
// VEHICLE MANAGEMENT FUNCTIONS (v4.3) - FIXED
// -----------------------------------------------------------------------------

// This function is duplicated - using the page-specific one from tools-grid
// The original at line ~600 will be called if this isn't found first

function cleanMyVehicle() {
  sendAction({ action: 'cleanVehicle', targetId: -1 });
  showToast('success', 'Vehiculo limpiado');
}

function tuneMyVehicle() {
  sendAction({ action: 'tuneVehicle', targetId: -1 });
  showToast('success', 'Vehiculo tuneado al maximo');
}

function toggleGhostVehicle() {
  const current = window.__lyxGhostVehicleEnabled === true;
  const next = !current;
  window.__lyxGhostVehicleEnabled = next;
  sendAction({ action: "ghostVehicle", targetId: -1, enabled: next });
  document
    .getElementById("btnGhostVehicle")
    ?.classList.toggle("active", next);
  showToast("info", next ? "Ghost Veh activado" : "Ghost Veh desactivado");
}

function setVehicleColors() {
  const primary = document.getElementById('vehiclePrimaryColor')?.value || '#ff0000';
  const secondary = document.getElementById('vehicleSecondaryColor')?.value || '#000000';
  // Convert hex to color index (simplified - FiveM uses color indices 0-160)
  const primaryIdx = hexToColorIndex(primary);
  const secondaryIdx = hexToColorIndex(secondary);
  sendAction({ action: 'setVehicleColor', targetId: -1, primary: primaryIdx, secondary: secondaryIdx });
  showToast('success', 'Colores aplicados');
}

function applyVehicleLivery() {
  const livery = parseInt(document.getElementById('vehicleLiveryIndex')?.value ?? '-1', 10);
  sendAction({ action: 'setVehicleLivery', targetId: -1, livery: Number.isFinite(livery) ? livery : -1 });
  showToast('success', 'Livery aplicado');
}

function applyVehicleExtra() {
  const extraId = parseInt(document.getElementById('vehicleExtraId')?.value ?? '0', 10);
  const enabled = (document.getElementById('vehicleExtraEnabled')?.value ?? '1') === '1';
  if (!Number.isFinite(extraId) || extraId < 0 || extraId > 20) {
    showToast('error', 'Extra ID invalido (0-20)');
    return;
  }
  sendAction({ action: 'setVehicleExtra', targetId: -1, extraId, enabled });
  showToast('success', `Extra ${extraId} ${enabled ? 'activado' : 'desactivado'}`);
}

function applyVehicleNeon() {
  const hex = document.getElementById('vehicleNeonColor')?.value || '#00ccff';
  const enabled = (document.getElementById('vehicleNeonEnabled')?.value ?? '1') === '1';
  sendAction({ action: 'setVehicleNeon', targetId: -1, enabled, neonColor: hexToRgb(hex) });
  showToast('success', 'Neon actualizado');
}

function applyVehicleModkit() {
  const mods = {
    engine: parseInt(document.getElementById('vehicleModEngine')?.value ?? '-1', 10),
    brakes: parseInt(document.getElementById('vehicleModBrakes')?.value ?? '-1', 10),
    transmission: parseInt(document.getElementById('vehicleModTransmission')?.value ?? '-1', 10),
    suspension: parseInt(document.getElementById('vehicleModSuspension')?.value ?? '-1', 10),
    armor: parseInt(document.getElementById('vehicleModArmor')?.value ?? '-1', 10),
    turbo: (document.getElementById('vehicleModTurbo')?.value ?? '1') === '1'
  };

  const clamp = (v) => {
    if (!Number.isFinite(v)) return -1;
    if (v < -1) return -1;
    if (v > 5) return 5;
    return v;
  };

  mods.engine = clamp(mods.engine);
  mods.brakes = clamp(mods.brakes);
  mods.transmission = clamp(mods.transmission);
  mods.suspension = clamp(mods.suspension);
  mods.armor = clamp(mods.armor);

  sendAction({ action: 'setVehicleModkit', targetId: -1, mods });
  showToast('success', 'Modkit aplicado');
}

function applyVehicleWheelSmoke() {
  const hex = document.getElementById('vehicleSmokeColor')?.value || '#ffffff';
  sendAction({ action: 'setVehicleWheelSmoke', targetId: -1, smokeColor: hexToRgb(hex) });
  showToast('success', 'Humo de ruedas actualizado');
}

function applyVehiclePaintAdvanced() {
  const pearlescent = parseInt(document.getElementById('vehiclePearlescentColor')?.value ?? '0', 10);
  const wheelColor = parseInt(document.getElementById('vehicleWheelColor')?.value ?? '0', 10);
  if (!Number.isFinite(pearlescent) || pearlescent < 0 || pearlescent > 160) {
    showToast('error', 'Pearlescent invalido (0-160)');
    return;
  }
  if (!Number.isFinite(wheelColor) || wheelColor < 0 || wheelColor > 160) {
    showToast('error', 'Wheel color invalido (0-160)');
    return;
  }
  sendAction({ action: 'setVehiclePaintAdvanced', targetId: -1, pearlescent, wheelColor });
  showToast('success', 'Pintura avanzada aplicada');
}

function applyVehicleXenon() {
  const enabled = (document.getElementById('vehicleXenonEnabled')?.value ?? '1') === '1';
  const xenonColor = parseInt(document.getElementById('vehicleXenonColor')?.value ?? '-1', 10);
  if (!Number.isFinite(xenonColor) || xenonColor < -1 || xenonColor > 13) {
    showToast('error', 'Color xenon invalido (-1 a 13)');
    return;
  }
  sendAction({ action: 'setVehicleXenon', targetId: -1, enabled, xenonColor });
  showToast('success', 'Xenon actualizado');
}

function hexToRgb(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result ? {
    r: parseInt(result[1], 16),
    g: parseInt(result[2], 16),
    b: parseInt(result[3], 16)
  } : { r: 255, g: 0, b: 0 };
}

// Convert hex color to FiveM color index (approximation)
function hexToColorIndex(hex) {
  const rgb = hexToRgb(hex);
  // Match to closest basic color - this is simplified
  // In practice, FiveM uses SetVehicleCustomPrimaryColour for exact colors
  return rgb; // Return RGB object for custom color
}

function deleteNearbyVehicles() {
  if (confirm('Borrar todos los vehiculos cercanos?')) {
    sendAction({ action: 'deleteNearby' });
    showToast('warning', 'Vehiculos cercanos eliminados');
  }
}

function flipMyVehicle() {
  sendAction({ action: 'flipVehicle', targetId: -1 });
  showToast('success', 'Vehiculo volteado');
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - TELEPORT FAVORITES
// -----------------------------------------------------------------------------

let teleportFavorites = { defaults: [], custom: [] };

async function loadTeleportFavorites() {
  return new Promise((resolve) => {
    fetch(`https://${GetParentResourceName()}/getTeleportFavorites`, {
      method: 'POST',
      body: JSON.stringify({})
    }).then(r => r.json()).then(data => {
      teleportFavorites = data;
      resolve(data);
    }).catch(() => resolve({ defaults: [], custom: [] }));
  });
}

function showTeleportFavorites() {
  loadTeleportFavorites().then(() => {
    let html = '<div class="teleport-favorites-modal">';
    html += '<h3>Ubicaciones Favoritas</h3>';
    
    // Defaults
    if (teleportFavorites.defaults && teleportFavorites.defaults.length > 0) {
      html += '<h4>Predeterminados</h4><div class="favorites-grid">';
      teleportFavorites.defaults.forEach(loc => {
        html += `<button class="btn btn-secondary" onclick="teleportToFavorite(${JSON.stringify(loc).replace(/"/g, '&quot;')})">${loc.name}</button>`;
      });
      html += '</div>';
    }
    
    // Custom
    if (teleportFavorites.custom && teleportFavorites.custom.length > 0) {
      html += '<h4>Mis Favoritos</h4><div class="favorites-grid">';
      teleportFavorites.custom.forEach(loc => {
        html += `<div class="favorite-item">
          <span>${loc.name}</span>
          <button class="btn btn-sm btn-primary" onclick="teleportToFavorite({x:${loc.x},y:${loc.y},z:${loc.z},name:'${loc.name}'})">Ir</button>
          <button class="btn btn-sm btn-danger" onclick="deleteTeleportFavorite(${loc.id})">&times;</button>
        </div>`;
      });
      html += '</div>';
    }
    
    // Add new
    html += `<div class="add-favorite-section">
      <input type="text" id="newFavoriteName" placeholder="Nombre de la ubicacion" class="form-input">
      <button class="btn btn-success" onclick="saveCurrentPosition()">Guardar Posicion Actual</button>
    </div>`;
    
    html += '</div>';
    showInputModal('Teleport Favoritos', html);
  });
}

function teleportToFavorite(location) {
  sendAction({ action: 'teleportToFavorite', location: location });
  closeInputModal();
  showToast('success', `Teleportando a ${location.name || 'ubicacion'}`);
}

function saveCurrentPosition() {
  const name = document.getElementById('newFavoriteName')?.value?.trim();
  if (!name) {
    showToast('error', 'Ingresa un nombre para la ubicacion');
    return;
  }
  sendAction({ action: 'saveTeleportFavorite', name: name });
  closeInputModal();
  showToast('success', `Ubicacion guardada: ${name}`);
}

function deleteTeleportFavorite(favoriteId) {
  sendAction({ action: 'deleteTeleportFavorite', favoriteId: favoriteId });
  showToast('info', 'Ubicacion eliminada');
  // Refresh the modal
  setTimeout(() => showTeleportFavorites(), 500);
}

// Teleport player to player
function teleportPlayerToPlayer() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador primero');
    return;
  }
  showInputModal('Teleport Jugador a Jugador', 
    `<p>Teleportar jugador seleccionado (${selectedPlayer.name}) hacia otro jugador</p>
    <select id="targetPlayer2" class="form-select">${generatePlayerOptions()}</select>
    <button class="btn btn-primary btn-full" onclick="executePlayerToPlayer()">Teleportar</button>`
  );
}

function executePlayerToPlayer() {
  const target2 = document.getElementById('targetPlayer2')?.value;
  if (!target2) {
    showToast('error', 'Selecciona el jugador destino');
    return;
  }
  sendAction({ action: 'teleportPlayerToPlayer', player1: selectedPlayer.id, player2: parseInt(target2) });
  closeInputModal();
  showToast('success', 'Jugador teleportado');
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - WEAPON KITS
// -----------------------------------------------------------------------------

let weaponKits = [];

async function loadWeaponKits() {
  return new Promise((resolve) => {
    fetch(`https://${GetParentResourceName()}/getWeaponKits`, {
      method: 'POST',
      body: JSON.stringify({})
    }).then(r => r.json()).then(data => {
      weaponKits = data;
      resolve(data);
    }).catch(() => resolve([]));
  });
}

function showWeaponKitsModal() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador primero');
    return;
  }
  
  loadWeaponKits().then(() => {
    let html = '<div class="weapon-kits-modal">';
    html += '<h3>Kits de Armas</h3>';
    html += '<p>Dar kit a: ' + selectedPlayer.name + '</p>';
    html += '<div class="kits-grid">';
    
    weaponKits.forEach(kit => {
      const weaponCount = kit.weapons ? kit.weapons.length : 0;
      html += `<div class="kit-card" onclick="giveWeaponKit('${kit.id}')">
        <h4>${kit.name}</h4>
        <p>${kit.description || ''}</p>
        <span class="kit-count">${weaponCount} armas</span>
      </div>`;
    });
    
    html += '</div></div>';
    showInputModal('Kits de Armas', html);
  });
}

function giveWeaponKit(kitId) {
  if (!selectedPlayer) return;
  sendAction({ action: 'giveWeaponKit', targetId: selectedPlayer.id, kitId: kitId });
  closeInputModal();
  showToast('success', 'Kit entregado');
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - BAN MANAGEMENT
// -----------------------------------------------------------------------------

function showEditBanModal(banId, currentReason, currentDuration) {
  showInputModal('Editar Ban', `
    <div class="edit-ban-form">
      <label>Razon:</label>
      <input type="text" id="editBanReason" value="${currentReason || ''}" class="form-input">
      <label>Duracion (horas, 0 = permanente):</label>
      <input type="number" id="editBanDuration" value="${currentDuration || 24}" class="form-input">
      <button class="btn btn-primary btn-full" onclick="submitEditBan(${banId})">Guardar Cambios</button>
    </div>
  `);
}

function submitEditBan(banId) {
  const reason = document.getElementById('editBanReason')?.value?.trim();
  const duration = document.getElementById('editBanDuration')?.value;
  sendAction({ action: 'editBan', banId: banId, reason: reason, duration: duration });
  closeInputModal();
  showToast('success', 'Ban actualizado');
}

async function exportBans() {
  showToast('info', 'Exportando bans...');
  fetch(`https://${GetParentResourceName()}/exportBans`, {
    method: 'POST',
    body: JSON.stringify({})
  }).then(r => r.json()).then(data => {
    if (data.success) {
      // Create download
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `lyxpanel_bans_${new Date().toISOString().split('T')[0]}.json`;
      a.click();
      URL.revokeObjectURL(url);
      showToast('success', `${data.bans.length} bans exportados`);
    } else {
      showToast('error', data.error || 'Error al exportar');
    }
  }).catch(err => showToast('error', 'Error de conexion'));
}

function showImportBansModal() {
  showInputModal('Importar Bans', `
    <div class="import-bans-form">
      <p>Pega el contenido JSON de los bans a importar:</p>
      <textarea id="importBansData" class="form-textarea" rows="10" placeholder='[{"identifier":"license:xxx","reason":"...","permanent":false}]'></textarea>
      <button class="btn btn-warning btn-full" onclick="submitImportBans()">Importar Bans</button>
    </div>
  `);
}

function submitImportBans() {
  const data = document.getElementById('importBansData')?.value?.trim();
  try {
    const bans = JSON.parse(data);
    if (!Array.isArray(bans)) {
      showToast('error', 'Formato invalido: debe ser un array');
      return;
    }
    sendAction({ action: 'importBans', bans: bans });
    closeInputModal();
    showToast('success', `Importando ${bans.length} bans...`);
  } catch (e) {
    showToast('error', 'JSON invalido');
  }
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - VEHICLE ADVANCED
// -----------------------------------------------------------------------------

function bringTargetVehicle() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador');
    return;
  }
  sendAction({ action: 'bringVehicle', targetId: selectedPlayer.id });
  showToast('success', 'Trayendo vehiculo...');
}

function toggleTargetDoors() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador');
    return;
  }
  sendAction({ action: 'toggleVehicleDoors', targetId: selectedPlayer.id, doorIndex: -1 });
  showToast('info', 'Puertas alternadas');
}

function toggleTargetEngine() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador');
    return;
  }
  sendAction({ action: 'toggleVehicleEngine', targetId: selectedPlayer.id });
  showToast('info', 'Motor alternado');
}

function setTargetFuel() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador');
    return;
  }
  showInputModal('Establecer Combustible', `
    <label>Nivel de combustible (0-100):</label>
    <input type="range" id="fuelLevel" min="0" max="100" value="100" oninput="document.getElementById('fuelDisplay').textContent = this.value + '%'">
    <span id="fuelDisplay">100%</span>
    <button class="btn btn-primary btn-full" onclick="submitSetFuel()">Aplicar</button>
  `);
}

function submitSetFuel() {
  const level = document.getElementById('fuelLevel')?.value || 100;
  sendAction({ action: 'setVehicleFuel', targetId: selectedPlayer.id, fuelLevel: parseInt(level) });
  closeInputModal();
  showToast('success', `Combustible: ${level}%`);
}

function warpIntoTargetVehicle() {
  if (!selectedPlayer) {
    showToast('error', 'Selecciona un jugador');
    return;
  }
  sendAction({ action: 'warpIntoVehicle', targetId: -1, driverPlayerId: selectedPlayer.id });
  showToast('success', 'Entrando en vehiculo...');
}

function warpOutOfVehicle() {
  sendAction({ action: 'warpOutOfVehicle', targetId: -1 });
  showToast('info', 'Saliendo del vehiculo...');
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - REPORT PRIORITY
// -----------------------------------------------------------------------------

const REPORT_PRIORITIES = [
  { id: 'low', label: 'Baja', color: '#3b82f6', icon: '<i class=\"fas fa-circle\" style=\"color:#3b82f6\"></i>' },
  { id: 'medium', label: 'Media', color: '#f59e0b', icon: '<i class=\"fas fa-circle\" style=\"color:#f59e0b\"></i>' },
  { id: 'high', label: 'Alta', color: '#ef4444', icon: '<i class=\"fas fa-circle\" style=\"color:#ef4444\"></i>' },
  { id: 'critical', label: 'Critica', color: '#dc2626', icon: '<i class=\"fas fa-circle\" style=\"color:#dc2626\"></i>' }
];

function setReportPriority(reportId, priority) {
  sendAction({ action: 'setReportPriority', reportId: reportId, priority: priority });
  showToast('success', `Prioridad cambiada a: ${priority}`);
}

function sendReportMessage(reportId, targetId) {
  showInputModal('Mensaje Privado', `
    <label>Mensaje al jugador:</label>
    <textarea id="reportMessage" class="form-textarea" rows="3" placeholder="Escribe tu mensaje..."></textarea>
    <button class="btn btn-primary btn-full" onclick="submitReportMessage(${reportId}, ${targetId})">Enviar</button>
  `);
}

function submitReportMessage(reportId, targetId) {
  const message = document.getElementById('reportMessage')?.value?.trim();
  if (!message) {
    showToast('error', 'Escribe un mensaje');
    return;
  }
  sendAction({ action: 'sendReportMessage', reportId: reportId, targetId: targetId, message: message });
  closeInputModal();
  showToast('success', 'Mensaje enviado');
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - ADMIN RANKINGS
// -----------------------------------------------------------------------------

async function showAdminRankings(period = 'week') {
  showToast('info', 'Cargando rankings...');
  fetch(`https://${GetParentResourceName()}/getAdminRankings`, {
    method: 'POST',
    body: JSON.stringify({ period: period })
  }).then(r => r.json()).then(rankings => {
    let html = '<div class="admin-rankings">';
    html += '<h3>Ranking de Administradores</h3>';
    html += `<div class="period-selector">
      <button class="btn ${period === 'day' ? 'btn-primary' : 'btn-secondary'}" onclick="showAdminRankings('day')">Hoy</button>
      <button class="btn ${period === 'week' ? 'btn-primary' : 'btn-secondary'}" onclick="showAdminRankings('week')">Semana</button>
      <button class="btn ${period === 'month' ? 'btn-primary' : 'btn-secondary'}" onclick="showAdminRankings('month')">Mes</button>
      <button class="btn ${period === 'all' ? 'btn-primary' : 'btn-secondary'}" onclick="showAdminRankings('all')">Todo</button>
    </div>`;
    
    if (rankings && rankings.length > 0) {
      html += '<table class="rankings-table"><thead><tr><th>#</th><th>Admin</th><th>Acciones</th><th>Kicks</th><th>Bans</th></tr></thead><tbody>';
      rankings.forEach((admin, index) => {
        const medal = index + 1;
        html += `<tr>
          <td>${medal}</td>
          <td>${admin.admin_name || 'Unknown'}</td>
          <td><strong>${admin.total_actions || 0}</strong></td>
          <td>${admin.total_kicks || 0}</td>
          <td>${admin.total_bans || 0}</td>
        </tr>`;
      });
      html += '</tbody></table>';
    } else {
      html += '<p class="no-data">No hay datos para este periodo</p>';
    }
    
    html += '</div>';
    showInputModal('Rankings', html);
  }).catch(() => showToast('error', 'Error cargando rankings'));
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - OUTFITS
// -----------------------------------------------------------------------------

async function showOutfitsModal() {
  fetch(`https://${GetParentResourceName()}/getMyOutfits`, {
    method: 'POST',
    body: JSON.stringify({})
  }).then(r => r.json()).then(outfits => {
    let html = '<div class="outfits-modal">';
    html += '<h3>Mis Outfits</h3>';
    
    // Save current outfit
    html += `<div class="save-outfit-section">
      <input type="text" id="newOutfitName" placeholder="Nombre del outfit" class="form-input">
      <button class="btn btn-success" onclick="saveCurrentOutfit()">Guardar Outfit Actual</button>
    </div>`;
    
    if (outfits && outfits.length > 0) {
      html += '<div class="outfits-list">';
      outfits.forEach(outfit => {
        html += `<div class="outfit-item">
          <span>${outfit.outfit_name}</span>
          <div class="outfit-actions">
            <button class="btn btn-sm btn-primary" onclick="loadOutfit(${outfit.id})">Cargar</button>
            <button class="btn btn-sm btn-danger" onclick="deleteOutfit(${outfit.id})">&times;</button>
          </div>
        </div>`;
      });
      html += '</div>';
    } else {
      html += '<p class="no-data">No tienes outfits guardados</p>';
    }
    
    html += '</div>';
    showInputModal('Outfits', html);
  }).catch(() => showToast('error', 'Error cargando outfits'));
}

function saveCurrentOutfit() {
  const name = document.getElementById('newOutfitName')?.value?.trim();
  if (!name) {
    showToast('error', 'Ingresa un nombre para el outfit');
    return;
  }
  sendAction({ action: 'saveOutfit', name: name });
  closeInputModal();
  showToast('success', `Outfit guardado: ${name}`);
}

function loadOutfit(outfitId) {
  sendAction({ action: 'loadOutfit', outfitId: outfitId });
  closeInputModal();
  showToast('success', 'Outfit cargado');
}

function deleteOutfit(outfitId) {
  sendAction({ action: 'deleteOutfit', outfitId: outfitId });
  showToast('info', 'Outfit eliminado');
  setTimeout(() => showOutfitsModal(), 500);
}
// -----------------------------------------------------------------------------
// v4.5 NEW FEATURES - ADMIN HUD & MISC
// -----------------------------------------------------------------------------

let adminHudEnabled = false;

function toggleAdminHud() {
  adminHudEnabled = !adminHudEnabled;
  sendAction({ action: 'toggleAdminHud', enabled: adminHudEnabled });
  showToast('info', adminHudEnabled ? 'HUD Admin ACTIVADO' : 'HUD Admin DESACTIVADO');
}

function reloadServerConfig() {
  if (confirm('Recargar configuracion del servidor?')) {
    sendAction({ action: 'reloadConfig' });
    showToast('info', 'Recargando configuracion...');
  }
}

// Helper to generate player options for selects
function generatePlayerOptions() {
  if (!window.playersList) return '<option value="">No hay jugadores</option>';
  return window.playersList.map(p => `<option value="${p.id}">${p.name} [${p.id}]</option>`).join('');
}
// -----------------------------------------------------------------------------
// INITIALIZATION
// -----------------------------------------------------------------------------

document.addEventListener('DOMContentLoaded', () => {
  CommandPalette.init();
  Toast.init();
  console.log('[LyxPanel] v4.5 complete edition loaded - 50+ new features');
});




