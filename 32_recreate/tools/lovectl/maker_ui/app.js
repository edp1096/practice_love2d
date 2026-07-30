"use strict";

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) =>
  Array.from(root.querySelectorAll(selector));

const token = document.body.dataset.makerToken || "";
document.body.removeAttribute("data-maker-token");

class APIError extends Error {
  constructor(message, status = 0, data = null) {
    super(message);
    this.name = "APIError";
    this.status = status;
    this.data = data;
  }
}

const state = {
  project: null,
  graph: { total: 0, edge_count: 0, nodes: [] },
  selectedKind: "all",
  search: "",
  selectedID: "",
  current: null,
  revision: "",
  draft: null,
  originalDefinition: null,
  dirty: false,
  activeTab: "form",
  jsonDirty: false,
  jsonParseTimer: null,
  openPaths: new Set(["[]"]),
  arrayLimits: new Map(),
  mapSource: "",
  mapRevision: "",
  mapDraft: null,
  originalMapDraft: null,
  screenshotLive: true,
  screenshotTimer: null,
  screenshotBusy: false,
  screenshotURL: "",
};

let requestTail = Promise.resolve();

function enqueueRequest(task) {
  const result = requestTail.then(task, task);
  requestTail = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
}

async function apiJSON(path, options = {}) {
  return enqueueRequest(async () => {
    const requestOptions = {
      method: options.method || "GET",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        ...(options.headers || {}),
      },
    };
    if (options.body !== undefined) {
      requestOptions.headers["Content-Type"] = "application/json";
      requestOptions.body = JSON.stringify(options.body);
    }
    if (requestOptions.method !== "GET" && requestOptions.method !== "HEAD") {
      requestOptions.headers["X-Recreate-Token"] = token;
    }

    let response;
    try {
      response = await fetch(path, requestOptions);
    } catch (error) {
      throw new APIError(`Maker 서버에 연결할 수 없습니다: ${error.message}`);
    }

    let payload;
    try {
      payload = await response.json();
    } catch {
      throw new APIError(
        `서버가 올바른 JSON을 반환하지 않았습니다 (HTTP ${response.status})`,
        response.status,
      );
    }
    if (!response.ok || !payload.ok) {
      throw new APIError(
        payload.error || `요청이 실패했습니다 (HTTP ${response.status})`,
        response.status,
        payload.data,
      );
    }
    return payload.data;
  });
}

function createElement(tag, className = "", text = "") {
  const element = document.createElement(tag);
  if (className) {
    element.className = className;
  }
  if (text !== "") {
    element.textContent = text;
  }
  return element;
}

function deepClone(value) {
  if (typeof structuredClone === "function") {
    return structuredClone(value);
  }
  return JSON.parse(JSON.stringify(value));
}

function stableText(value) {
  return JSON.stringify(value);
}

function shortRevision(revision) {
  if (!revision) {
    return "—";
  }
  const value = String(revision);
  if (value.length <= 18) {
    return value;
  }
  return `${value.slice(0, 9)}…${value.slice(-7)}`;
}

function setRuntimeStatus(text, kind = "") {
  const element = $("#runtime-status");
  element.textContent = text;
  element.className = `status-pill${kind ? ` ${kind}` : ""}`;
}

function toast(message, kind = "") {
  const region = $("#toast-region");
  const item = createElement("div", `toast${kind ? ` ${kind}` : ""}`, message);
  region.append(item);
  window.setTimeout(() => {
    item.remove();
  }, kind === "error" ? 6500 : 3600);
}

function errorMessage(error) {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function graphNodes() {
  return Array.isArray(state.graph?.nodes) ? state.graph.nodes : [];
}

const preferredKinds = [
  "stage",
  "actor",
  "ability",
  "dialogue",
  "quest",
  "item",
  "shop",
  "encounter",
  "projectile",
  "status",
  "sprite",
  "asset",
  "locale",
];

function kindRank(kind) {
  const rank = preferredKinds.indexOf(kind);
  return rank === -1 ? preferredKinds.length : rank;
}

function sortedNodes(nodes = graphNodes()) {
  return [...nodes].sort((left, right) => {
    const kindDifference = kindRank(left.kind) - kindRank(right.kind);
    if (kindDifference !== 0) {
      return kindDifference;
    }
    if (left.kind !== right.kind) {
      return String(left.kind).localeCompare(String(right.kind));
    }
    return String(left.id).localeCompare(String(right.id));
  });
}

function setGraph(graph) {
  if (!graph || !Array.isArray(graph.nodes)) {
    return;
  }
  state.graph = graph;
  if (state.current) {
    const currentNode = graph.nodes.find(
      (node) => node.id === state.current.id,
    );
    if (currentNode) {
      state.current.dependencies = currentNode.dependencies || [];
      state.current.dependents = currentNode.dependents || [];
      renderRelations();
    }
  }
  renderKinds();
  renderContentList();
  populatePreviewIDs();
  updateCreateReference();
}

function renderKinds() {
  const counts = new Map();
  for (const node of graphNodes()) {
    counts.set(node.kind, (counts.get(node.kind) || 0) + 1);
  }
  const kinds = [...counts.keys()].sort((left, right) => {
    const rankDifference = kindRank(left) - kindRank(right);
    return rankDifference || left.localeCompare(right);
  });
  if (
    state.selectedKind !== "all" &&
    !counts.has(state.selectedKind)
  ) {
    state.selectedKind = "all";
  }

  const container = $("#kind-list");
  container.replaceChildren();

  const all = createElement("button", "kind-button", "전체");
  all.type = "button";
  all.dataset.kind = "all";
  if (state.selectedKind === "all") {
    all.classList.add("active");
  }
  const allCount = createElement("span", "kind-count", String(graphNodes().length));
  all.append(allCount);
  container.append(all);

  for (const kind of kinds) {
    const button = createElement("button", "kind-button", kind);
    button.type = "button";
    button.dataset.kind = kind;
    if (state.selectedKind === kind) {
      button.classList.add("active");
    }
    button.append(
      createElement("span", "kind-count", String(counts.get(kind))),
    );
    container.append(button);
  }
}

function sourceBasename(source) {
  const parts = String(source || "").split("/");
  return parts[parts.length - 1] || "source 없음";
}

function filteredNodes() {
  const query = state.search.trim().toLocaleLowerCase();
  return sortedNodes().filter((node) => {
    if (state.selectedKind !== "all" && node.kind !== state.selectedKind) {
      return false;
    }
    if (!query) {
      return true;
    }
    return (
      String(node.id).toLocaleLowerCase().includes(query) ||
      String(node.kind).toLocaleLowerCase().includes(query) ||
      String(node.source || "").toLocaleLowerCase().includes(query)
    );
  });
}

function renderContentList() {
  const nodes = filteredNodes();
  const container = $("#content-list");
  container.replaceChildren();
  $("#content-count").textContent = `${nodes.length}개`;
  $("#graph-edge-count").textContent =
    `참조 ${Number(state.graph?.edge_count || 0)}개`;

  if (nodes.length === 0) {
    container.append(
      createElement("div", "list-empty", "조건에 맞는 콘텐츠가 없습니다."),
    );
    return;
  }

  for (const node of nodes) {
    const button = createElement("button", "content-item");
    button.type = "button";
    button.dataset.contentId = node.id;
    button.setAttribute("role", "option");
    button.setAttribute(
      "aria-selected",
      node.id === state.selectedID ? "true" : "false",
    );
    if (node.id === state.selectedID) {
      button.classList.add("active");
    }
    button.append(
      createElement("span", "content-item-id", node.id),
      createElement("span", "content-item-kind", node.kind),
      createElement(
        "span",
        "content-item-source",
        sourceBasename(node.source),
      ),
    );
    container.append(button);
  }
}

function renderProject(data) {
  const runtime = data?.runtime || {};
  const world = data?.world || {};
  const worldStage = world?.stage || {};
  const flow = world?.game_flow || {};

  $("#project-name").textContent = data?.name || runtime.title || "Recreate 프로젝트";
  $("#project-profile").textContent = runtime.profile || "custom";
  $("#project-stage").textContent =
    runtime.stage_id || worldStage.id || "—";
  $("#world-stage").textContent =
    worldStage.id || runtime.stage_id || "—";
  $("#world-entities").textContent =
    world.count === undefined ? "—" : String(world.count);
  $("#world-flow").textContent = flow.mode || "playing";
  setRuntimeStatus("연결됨");
}

async function refreshProject({ initial = false } = {}) {
  setRuntimeStatus("동기화 중", "pending");
  try {
    const data = await apiJSON("/api/project");
    state.project = data;
    renderProject(data);
    if (data.graph) {
      setGraph(data.graph);
    }
    if (initial && !state.selectedID) {
      const nodes = sortedNodes();
      const requestedID = new URLSearchParams(window.location.search)
        .get("content");
      const initialNode =
        nodes.find((node) => node.id === requestedID) ||
        nodes.find((node) => node.id === "stage.village") ||
        nodes.find((node) => node.kind === "stage") ||
        nodes[0];
      if (initialNode) {
        await selectContent(initialNode.id, { skipDirtyCheck: true });
      }
    }
  } catch (error) {
    setRuntimeStatus("연결 오류", "error");
    toast(errorMessage(error), "error");
    throw error;
  }
}

async function refreshGraph(force = true, { notify = true } = {}) {
  try {
    const graph = await apiJSON(`/api/graph${force ? "?refresh=1" : ""}`);
    setGraph(graph);
    if (notify) {
      toast("콘텐츠 참조 그래프를 갱신했습니다.", "success");
    }
    return graph;
  } catch (error) {
    if (notify) {
      toast(errorMessage(error), "error");
    }
    throw error;
  }
}

function confirmDiscard() {
  if (!state.dirty) {
    return true;
  }
  return window.confirm(
    "저장하지 않은 변경이 있습니다. 변경을 버리고 이동하시겠습니까?",
  );
}

function showEditorLoading(contentID) {
  $("#empty-editor").hidden = true;
  $("#editor-shell").hidden = false;
  $("#content-id").textContent = contentID;
  $("#content-kind").textContent = "loading";
  $("#content-source").textContent = "콘텐츠를 읽는 중…";
  $("#content-revision").textContent = "revision —";
  $("#structured-form").replaceChildren();
  showValidation("neutral", "콘텐츠를 읽는 중입니다.");
}

function parseMapJSON(value, fallback) {
  if (!value) {
    return deepClone(fallback);
  }
  try {
    return JSON.parse(value);
  } catch {
    return deepClone(fallback);
  }
}

function hydrateMapResult(result) {
  const hydrated = deepClone(result);
  const worldPages = parseMapJSON(
    hydrated.properties?.world_pages,
    [],
  );
  hydrated.world_pages = Array.isArray(worldPages)
    ? worldPages.map((page) => ({
      ...page,
      tint: Array.isArray(page?.tint) ? page.tint : [0, 0, 0, 0],
      layers: Array.isArray(page?.layers) ? page.layers : [],
      on_enter: Array.isArray(page?.on_enter) ? page.on_enter : [],
      on_exit: Array.isArray(page?.on_exit) ? page.on_exit : [],
    }))
    : [];
  hydrated.objects = (hydrated.objects || []).map((object) => {
    const properties = object.properties || {};
    return {
      ...object,
      actor: properties.actor || "",
      spawn_id: properties.id || object.name || "",
      tags: properties.tags || "",
      actor_tag: properties.actor_tag || "",
      cooldown: Number(
        properties.cooldown ??
        (object.class === "portal" ? 0.25 : 0),
      ),
      once: properties.once === "true",
      target_stage: properties.target_stage || "",
      target_spawn: properties.target_spawn || "",
      actions: object.class === "trigger"
        ? parseMapJSON(properties.actions, [])
        : undefined,
      pages: object.class === "trigger" && properties.pages
        ? parseMapJSON(properties.pages, [])
        : undefined,
      condition: ["trigger", "region"].includes(object.class) &&
        properties.condition
        ? parseMapJSON(properties.condition, null)
        : null,
      on_enter: object.class === "region"
        ? parseMapJSON(properties.on_enter, [])
        : undefined,
      on_exit: object.class === "region"
        ? parseMapJSON(properties.on_exit, [])
        : undefined,
    };
  });
  return hydrated;
}

async function loadSelectedMap(definition) {
  state.mapSource = "";
  state.mapRevision = "";
  state.mapDraft = null;
  state.originalMapDraft = null;
  if (definition?.kind !== "stage") {
    return;
  }
  const source =
    definition.metadata?.source ||
    definition.tilemap?.source ||
    "";
  if (!String(source).startsWith("game/maps/")) {
    return;
  }
  const result = await apiJSON(
    `/api/map?source=${encodeURIComponent(source)}`,
  );
  const hydrated = hydrateMapResult(result);
  state.mapSource = source;
  state.mapRevision = String(result.revision || "");
  state.mapDraft = hydrated;
  state.originalMapDraft = deepClone(hydrated);
}

async function selectContent(
  contentID,
  { skipDirtyCheck = false, force = false } = {},
) {
  if (!contentID) {
    return;
  }
  if (!force && contentID === state.selectedID && state.current) {
    return;
  }
  if (!skipDirtyCheck && !confirmDiscard()) {
    return;
  }

  state.selectedID = contentID;
  state.dirty = false;
  state.current = null;
  state.mapSource = "";
  state.mapRevision = "";
  state.mapDraft = null;
  state.originalMapDraft = null;
  renderContentList();
  showEditorLoading(contentID);

  try {
    const content = await apiJSON(
      `/api/content?id=${encodeURIComponent(contentID)}`,
    );
    if (
      !content ||
      !content.definition ||
      Array.isArray(content.definition) ||
      typeof content.definition !== "object"
    ) {
      throw new Error("서버가 올바른 콘텐츠 정의를 반환하지 않았습니다.");
    }
    state.current = content;
    state.revision = String(content.revision || "");
    state.draft = deepClone(content.definition);
    state.originalDefinition = deepClone(content.definition);
    state.dirty = false;
    state.jsonDirty = false;
    state.openPaths = new Set(["[]"]);
    state.arrayLimits = new Map();
    try {
      await loadSelectedMap(state.draft);
    } catch (error) {
      state.mapSource = "";
      state.mapRevision = "";
      state.mapDraft = null;
      state.originalMapDraft = null;
      toast(`맵 편집 정보를 읽지 못했습니다: ${errorMessage(error)}`, "error");
    }
    renderEditor();
    syncPreviewToSelection();
  } catch (error) {
    state.current = null;
    $("#empty-editor").hidden = false;
    $("#editor-shell").hidden = true;
    toast(errorMessage(error), "error");
  } finally {
    renderContentList();
  }
}

function setDirty(value) {
  state.dirty = Boolean(value);
  $("#dirty-indicator").hidden = !state.dirty;
}

function updateDirtyFromDraft() {
  if (!state.draft || !state.originalDefinition) {
    setDirty(false);
    return;
  }
  const contentDirty =
    stableText(state.draft) !== stableText(state.originalDefinition);
  const mapDirty =
    state.mapDraft &&
    state.originalMapDraft &&
    stableText(state.mapDraft) !== stableText(state.originalMapDraft);
  setDirty(contentDirty || Boolean(mapDirty));
}

function renderEditor() {
  const content = state.current;
  if (!content) {
    return;
  }
  $("#empty-editor").hidden = true;
  $("#editor-shell").hidden = false;
  $("#content-kind").textContent = content.kind || state.draft.kind || "unknown";
  $("#content-id").textContent = content.id || state.selectedID;
  $("#content-source").textContent = content.source || "source 없음";
  $("#content-revision").textContent =
    `revision ${shortRevision(state.revision)}`;
  $("#readonly-indicator").hidden = !content.read_only;
  $("#save-content").disabled = Boolean(content.read_only);
  $("#preview-selected").disabled = ![
    "stage",
    "actor",
    "dialogue",
    "ability",
  ].includes(content.kind);
  setDirty(state.dirty);
  renderStructuredForm();
  syncJSONFromDraft();
  renderRelations();
  switchTab(state.activeTab, { skipJSONParse: true });
  showValidation(
    "neutral",
    state.mapDraft
      ? "generated stage 본문은 읽기 전용입니다. 맵 카드의 '맵 변경 적용'은 TMX를 검증·컴파일하고 실행 화면까지 갱신합니다."
      : content.read_only
      ? "이 파일은 생성물이거나 game/content 밖에 있어 저장할 수 없습니다. 검증과 미리보기는 가능합니다."
      : "수정 후 검증하거나 저장하세요. 저장은 전체 콘텐츠를 다시 검증합니다.",
  );
}

function pathKey(path) {
  return JSON.stringify(path);
}

function assignPath(element, path) {
  element.dataset.path = pathKey(path);
}

function readPath(element) {
  try {
    return JSON.parse(element.dataset.path || "[]");
  } catch {
    return [];
  }
}

function getAtPath(path) {
  const mapPath = path[0] === "@map";
  let value = mapPath ? state.mapDraft : state.draft;
  for (const segment of mapPath ? path.slice(1) : path) {
    if (value === null || value === undefined) {
      return undefined;
    }
    value = value[segment];
  }
  return value;
}

function setAtPath(path, value) {
  const mapPath = path[0] === "@map";
  const segments = mapPath ? path.slice(1) : path;
  if (segments.length === 0) {
    if (mapPath) {
      state.mapDraft = value;
    } else {
      state.draft = value;
    }
    return;
  }
  const parentPath = mapPath
    ? ["@map", ...segments.slice(0, -1)]
    : segments.slice(0, -1);
  const parent = getAtPath(parentPath);
  if (parent !== null && parent !== undefined) {
    parent[segments[segments.length - 1]] = value;
  }
}

function valueKind(value) {
  if (value === null) {
    return "null";
  }
  if (Array.isArray(value)) {
    return "array";
  }
  if (typeof value === "object") {
    return "object";
  }
  if (typeof value === "number") {
    return "number";
  }
  if (typeof value === "boolean") {
    return "boolean";
  }
  return "string";
}

const typeLabels = {
  string: "문자열",
  number: "숫자",
  boolean: "논리값",
  object: "객체",
  array: "배열",
  null: "null (비지원)",
};

const actionLabels = {
  show_notice: "화면 알림",
  start_cutscene: "컷신 시작",
  start_dialogue: "대화 시작",
  close_dialogue: "대화 닫기",
  start_quest: "퀘스트 시작",
  give_item: "아이템 지급",
  take_item: "아이템 회수",
  use_item: "아이템 사용",
  equip_item: "장비 장착",
  unequip_slot: "장비 해제",
  add_currency: "소지금 지급",
  spend_currency: "소지금 사용",
  open_shop: "상점 열기",
  close_shop: "상점 닫기",
  buy_item: "아이템 구매",
  sell_item: "아이템 판매",
  set_flag: "플래그 켜기",
  clear_flag: "플래그 끄기",
  set_world_time: "세계 시간 설정",
  advance_world_time: "세계 시간 경과",
  set_locale: "언어 변경",
  emit: "게임 이벤트 발행",
  heal: "체력 회복",
  damage: "피해",
  revive: "부활",
  stagger: "경직",
  invulnerable: "무적",
  knockback: "넉백",
  hitstop: "히트스톱",
  camera_shake: "카메라 흔들림",
  spawn_projectile: "발사체 생성",
  apply_status: "상태 효과 부여",
  remove_status: "상태 효과 제거",
  start_encounter: "인카운터 시작",
  start_turn_battle: "턴제 전투 시작",
  save_game: "게임 저장",
  finish_game: "게임 완료",
};

const conditionLabels = {
  always: "항상",
  all: "모두 만족",
  any: "하나 이상 만족",
  not: "반대",
  quest_state: "퀘스트 상태",
  quest_objective: "퀘스트 목표 진행",
  has_item: "아이템 보유",
  item_equipped: "장비 착용",
  currency_at_least: "소지금 이상",
  flag: "플래그",
  locale_is: "언어",
  dialogue_active: "대화 중",
  cutscene_active: "컷신 재생 중",
  shop_active: "상점 이용 중",
  health_at_most: "체력 이하",
  has_status: "상태 효과 보유",
  encounter_state: "인카운터 상태",
  turn_battle_state: "턴제 전투 상태",
  game_flow_state: "게임 진행 상태",
  time_between: "세계 시간 범위",
  region_active: "지역 내부",
};

function firstContentID(kind) {
  return sortedNodes().find((node) => node.kind === kind)?.id || "";
}

function actionPreset(type) {
  const item = firstContentID("item");
  const shop = firstContentID("shop");
  const presets = {
    show_notice: {
      type,
      text: "새 알림",
      tone: "info",
      duration: 3,
    },
    start_cutscene: { type, cutscene: firstContentID("cutscene") },
    start_dialogue: { type, dialogue: firstContentID("dialogue") },
    close_dialogue: { type },
    start_quest: { type, quest: firstContentID("quest") },
    give_item: { type, item, amount: 1 },
    take_item: { type, item, amount: 1 },
    use_item: { type, item },
    equip_item: { type, item },
    unequip_slot: { type, slot: "weapon" },
    add_currency: { type, amount: 10, reason: "maker.reward" },
    spend_currency: { type, amount: 10, reason: "maker.cost" },
    open_shop: { type, shop },
    close_shop: { type },
    buy_item: { type, shop, item, quantity: 1 },
    sell_item: { type, shop, item, quantity: 1 },
    set_flag: { type, name: "game.flag", value: true },
    clear_flag: { type, name: "game.flag" },
    set_world_time: { type, time: "18:00" },
    advance_world_time: { type, minutes: 60 },
    set_locale: { type, locale: firstContentID("locale") },
    emit: { type, name: "game.event", data: {} },
    heal: { type, amount: 10 },
    damage: { type, amount: 10 },
    revive: { type, amount: 25 },
    stagger: { type, duration: 0.25 },
    invulnerable: { type, duration: 0.25 },
    knockback: { type, distance: 40, duration: 0.15 },
    hitstop: { type, duration: 0.06 },
    camera_shake: { type, duration: 0.15, magnitude: 6 },
    spawn_projectile: { type, projectile: firstContentID("projectile") },
    apply_status: {
      type,
      status: firstContentID("status"),
      stacks: 1,
    },
    remove_status: { type, status: firstContentID("status") },
    start_encounter: { type, encounter: firstContentID("encounter") },
    start_turn_battle: {
      type,
      battle: firstContentID("turn_battle"),
    },
    save_game: { type },
    finish_game: { type },
  };
  return deepClone(presets[type] || { type });
}

function conditionPreset(type) {
  const presets = {
    always: { type },
    all: { type, conditions: [{ type: "always" }] },
    any: { type, conditions: [{ type: "always" }] },
    not: { type, condition: { type: "always" } },
    quest_state: {
      type,
      quest: firstContentID("quest"),
      state: "inactive",
    },
    quest_objective: {
      type,
      quest: firstContentID("quest"),
      objective: "",
      count: 1,
    },
    has_item: { type, item: firstContentID("item"), amount: 1 },
    item_equipped: { type, item: firstContentID("item") },
    currency_at_least: { type, amount: 0 },
    flag: { type, name: "game.flag", value: true },
    locale_is: { type, locale: firstContentID("locale") },
    dialogue_active: { type },
    cutscene_active: { type },
    shop_active: { type },
    health_at_most: { type, value: 50 },
    has_status: { type, status: firstContentID("status") },
    encounter_state: {
      type,
      encounter: firstContentID("encounter"),
      state: "active",
    },
    turn_battle_state: {
      type,
      battle: firstContentID("turn_battle"),
      state: "never",
    },
    game_flow_state: { type, state: "started" },
    time_between: {
      type,
      start: "18:00",
      finish: "06:00",
    },
    region_active: { type, id: "region.id" },
  };
  return deepClone(presets[type] || { type });
}

function isActionArrayPath(path) {
  const key = String(path[path.length - 1] || "");
  return key === "actions" || key === "on_complete" ||
    key.startsWith("on_") ||
    key.endsWith("_actions");
}

function semanticObjectRole(path, value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return "";
  }
  const type = String(value.type || "");
  if (Object.prototype.hasOwnProperty.call(actionLabels, type)) {
    return "action";
  }
  if (Object.prototype.hasOwnProperty.call(conditionLabels, type)) {
    return "condition";
  }
  const key = String(path[path.length - 1] || "");
  if (key === "condition") {
    return "condition";
  }
  if (
    typeof path[path.length - 1] === "number" &&
    String(path[path.length - 2] || "") === "conditions"
  ) {
    return "condition";
  }
  return "";
}

function sortedSemanticTypes(labels) {
  return Object.keys(labels).sort((left, right) =>
    labels[left].localeCompare(labels[right], "ko"));
}

function defaultForType(type) {
  switch (type) {
    case "number":
      return 0;
    case "boolean":
      return false;
    case "object":
      return {};
    case "array":
      return [];
    case "null":
      return null;
    default:
      return "";
  }
}

function typeSelect(value, path, locked = false) {
  const select = createElement("select", "type-select");
  select.dataset.editorRole = "type";
  assignPath(select, path);
  const kind = valueKind(value);
  for (const type of ["string", "number", "boolean", "object", "array"]) {
    const option = createElement("option", "", typeLabels[type]);
    option.value = type;
    option.selected = kind === type;
    select.append(option);
  }
  if (kind === "null") {
    const option = createElement("option", "", typeLabels.null);
    option.value = "null";
    option.selected = true;
    select.prepend(option);
  }
  select.disabled = locked;
  select.setAttribute("aria-label", "값 형식");
  return select;
}

function rootFieldLocked(path) {
  return (
    path.length === 1 &&
    ["schema_version", "kind", "id"].includes(String(path[0]))
  );
}

function keyLabel(key, path, parentKind, locked = false) {
  const wrapper = createElement("span", "field-key");
  const label = createElement(
    "span",
    parentKind === "array" ? "array-index" : "",
    parentKind === "array" ? `#${Number(key) + 1}` : String(key),
  );
  wrapper.append(label);
  if (parentKind === "object" && !locked) {
    const rename = createElement("button", "field-button", "✎");
    rename.type = "button";
    rename.dataset.editorAction = "rename";
    assignPath(rename, path);
    rename.title = "필드 이름 변경";
    rename.setAttribute("aria-label", `${String(key)} 필드 이름 변경`);
    wrapper.append(rename);
  }
  return wrapper;
}

function deleteButton(path, locked = false) {
  const button = createElement("button", "delete-button", "×");
  button.type = "button";
  button.dataset.editorAction = "delete";
  assignPath(button, path);
  button.disabled = locked;
  button.title = "삭제";
  button.setAttribute("aria-label", "값 삭제");
  return button;
}

const referenceFieldKinds = {
  actor: "actor",
  actor_id: "actor",
  ability: "ability",
  ability_id: "ability",
  battle: "turn_battle",
  cutscene: "cutscene",
  dialogue: "dialogue",
  encounter: "encounter",
  item: "item",
  item_id: "item",
  locale: "locale",
  projectile: "projectile",
  projectile_id: "projectile",
  quest: "quest",
  shop: "shop",
  skill: "turn_skill",
  stage: "stage",
  status: "status",
  status_id: "status",
  target_stage: "stage",
};

function semanticSelect(value, path, options, role = "") {
  const select = document.createElement("select");
  select.dataset.editorRole = "primitive";
  select.dataset.valueType = "string";
  if (role) {
    select.dataset.schemaRole = role;
  }
  assignPath(select, path);
  const known = new Set(options.map((option) => String(option.value)));
  if (value !== "" && !known.has(String(value))) {
    options.unshift({
      value: String(value),
      label: `${String(value)} (현재 값)`,
    });
  }
  for (const optionValue of options) {
    const option = createElement("option", "", optionValue.label);
    option.value = String(optionValue.value);
    option.selected = String(value) === option.value;
    select.append(option);
  }
  return select;
}

function schemaPrimitiveEditor(value, path) {
  if (typeof value !== "string" || path.length === 0) {
    return null;
  }
  const key = String(path[path.length - 1]);
  const parentPath = path.slice(0, -1);
  const parent = getAtPath(parentPath);
  if (
    key === "type" &&
    parent &&
    typeof parent === "object" &&
    !Array.isArray(parent)
  ) {
    const role = semanticObjectRole(parentPath, parent);
    const labels = role === "action"
      ? actionLabels
      : role === "condition"
        ? conditionLabels
        : null;
    if (labels) {
      return semanticSelect(
        value,
        path,
        sortedSemanticTypes(labels).map((type) => ({
          value: type,
          label: `${labels[type]} · ${type}`,
        })),
        `${role}-type`,
      );
    }
  }
  if (key === "tone") {
    return semanticSelect(
      value,
      path,
      ["info", "success", "warning"].map((tone) => ({
        value: tone,
        label: tone,
      })),
    );
  }
  if (key === "effect" && state.draft?.kind === "turn_skill") {
    return semanticSelect(
      value,
      path,
      ["damage", "heal"].map((item) => ({ value: item, label: item })),
    );
  }
  if (key === "target" && state.draft?.kind === "turn_skill") {
    return semanticSelect(
      value,
      path,
      ["enemy", "self"].map((item) => ({ value: item, label: item })),
    );
  }
  if (
    (key === "next" || key === "start") &&
    state.draft?.kind === "dialogue"
  ) {
    const options = [
      { value: "", label: "끝내기" },
      ...Object.keys(state.draft.nodes || {}).map((nodeID) => ({
        value: nodeID,
        label: nodeID,
      })),
    ];
    return semanticSelect(value, path, options);
  }
  const referenceKind = referenceFieldKinds[key];
  if (referenceKind) {
    const options = sortedNodes()
      .filter((node) => node.kind === referenceKind)
      .map((node) => ({ value: node.id, label: node.id }));
    if (options.length > 0) {
      return semanticSelect(value, path, options);
    }
  }
  if (key === "state" && parent?.type === "quest_state") {
    return semanticSelect(
      value,
      path,
      ["inactive", "active", "completed"].map((stateValue) => ({
        value: stateValue,
        label: stateValue,
      })),
    );
  }
  if (key === "state" && parent?.type === "game_flow_state") {
    return semanticSelect(
      value,
      path,
      ["started", "completed"].map((stateValue) => ({
        value: stateValue,
        label: stateValue,
      })),
    );
  }
  if (key === "state" && parent?.type === "turn_battle_state") {
    return semanticSelect(
      value,
      path,
      ["never", "active", "won", "lost", "escaped"].map((stateValue) => ({
        value: stateValue,
        label: stateValue,
      })),
    );
  }
  return null;
}

function primitiveEditor(value, path, locked) {
  const kind = valueKind(value);
  const wrapper = createElement("div", "field-value");
  let input;

  const schemaEditor = !locked && schemaPrimitiveEditor(value, path);
  if (schemaEditor) {
    wrapper.append(schemaEditor);
    return wrapper;
  }

  if (kind === "boolean") {
    const label = createElement("label", "boolean-control");
    input = document.createElement("input");
    input.type = "checkbox";
    input.checked = value;
    input.dataset.editorRole = "primitive";
    input.dataset.valueType = "boolean";
    assignPath(input, path);
    input.disabled = locked;
    label.append(input, createElement("span", "", value ? "true" : "false"));
    wrapper.append(label);
    return wrapper;
  }

  if (kind === "number") {
    input = document.createElement("input");
    input.type = "number";
    input.step = "any";
    input.value = Number.isFinite(value) ? String(value) : "0";
  } else if (kind === "null") {
    input = document.createElement("input");
    input.type = "text";
    input.value = "null";
    input.disabled = true;
  } else if (
    String(value).includes("\n") ||
    String(value).length > 90
  ) {
    input = document.createElement("textarea");
    input.rows = Math.min(8, Math.max(3, String(value).split("\n").length));
    input.value = String(value);
  } else {
    input = document.createElement("input");
    input.type = "text";
    input.value = String(value);
  }

  input.dataset.editorRole = "primitive";
  input.dataset.valueType = kind;
  assignPath(input, path);
  if (locked) {
    input.disabled = true;
    input.classList.add("locked-field");
  }
  wrapper.append(input);
  return wrapper;
}

function primitiveRow(value, path, key, parentKind) {
  const locked = rootFieldLocked(path);
  const row = createElement("div", "primitive-row");
  row.append(
    keyLabel(key, path, parentKind, locked),
    primitiveEditor(value, path, locked),
    typeSelect(value, path, locked),
    deleteButton(path, locked),
  );
  return row;
}

function orderedObjectKeys(value) {
  const priority = ["schema_version", "kind", "id", "name", "name_key"];
  const keys = Object.keys(value);
  return [
    ...priority.filter((key) => keys.includes(key)),
    ...keys.filter((key) => !priority.includes(key)),
  ];
}

function addRow(path, kind) {
  const row = createElement(
    "div",
    `add-row${kind === "array" ? " array-add" : ""}`,
  );
  assignPath(row, path);
  if (kind === "array" && isActionArrayPath(path)) {
    row.classList.add("command-add-row");
    const actionType = createElement("select", "command-type-select");
    actionType.dataset.editorRole = "new-action-type";
    for (const type of sortedSemanticTypes(actionLabels)) {
      const option = createElement(
        "option",
        "",
        `${actionLabels[type]} · ${type}`,
      );
      option.value = type;
      actionType.append(option);
    }
    actionType.value = "show_notice";
    const button = createElement("button", "add-button", "+ 명령 추가");
    button.type = "button";
    button.dataset.editorAction = "add-action";
    assignPath(button, path);
    row.append(actionType, button);
    return row;
  }
  if (kind === "object") {
    const key = document.createElement("input");
    key.type = "text";
    key.placeholder = "새 필드 이름";
    key.dataset.editorRole = "new-key";
    key.setAttribute("aria-label", "새 필드 이름");
    row.append(key);
  }

  const type = createElement("select", "type-select");
  type.dataset.editorRole = "new-type";
  for (const name of ["string", "number", "boolean", "object", "array"]) {
    const option = createElement("option", "", typeLabels[name]);
    option.value = name;
    type.append(option);
  }
  const button = createElement(
    "button",
    "add-button",
    kind === "array" ? "+ 항목 추가" : "+ 필드 추가",
  );
  button.type = "button";
  button.dataset.editorAction = "add";
  assignPath(button, path);
  row.append(type, button);
  return row;
}

function containerNode(value, path, key, parentKind, depth, root = false) {
  const kind = valueKind(value);
  const semanticRole = semanticObjectRole(path, value);
  const details = createElement(
    "details",
    `structure-node${root ? " root-node" : ""}` +
      `${semanticRole ? ` semantic-node ${semanticRole}-node` : ""}`,
  );
  assignPath(details, path);
  const keyForOpen = pathKey(path);
  details.open = root || state.openPaths.has(keyForOpen);

  const summary = document.createElement("summary");
  const locked = rootFieldLocked(path);
  summary.append(
    keyLabel(root ? "definition" : key, path, parentKind, locked || root),
    createElement(
      "span",
      "structure-summary",
      semanticRole
        ? `${
          semanticRole === "action"
            ? actionLabels[value.type] || value.type || "명령"
            : conditionLabels[value.type] || value.type || "조건"
        } · ${value.type || "종류 선택"}`
        : kind === "array"
        ? `${value.length}개 항목`
        : `${Object.keys(value).length}개 필드`,
    ),
  );
  if (!root) {
    if (semanticRole) {
      summary.append(
        createElement(
          "span",
          "semantic-kind",
          semanticRole === "action" ? "명령" : "조건",
        ),
        deleteButton(path, locked),
      );
    } else {
      summary.append(typeSelect(value, path, locked), deleteButton(path, locked));
    }
  }
  details.append(summary);

  const renderBody = () => {
    if (details.dataset.rendered === "1") {
      return;
    }
    details.dataset.rendered = "1";
    const body = createElement("div", "structure-body");
    const current = getAtPath(path);
    if (valueKind(current) === "array") {
      const limit = state.arrayLimits.get(keyForOpen) || 120;
      const visible = current.slice(0, limit);
      visible.forEach((child, index) => {
        body.append(renderValue(child, [...path, index], index, "array", depth + 1));
      });
      if (current.length > visible.length) {
        const more = createElement(
          "button",
          "add-button",
          `나머지 ${current.length - visible.length}개 중 더 보기`,
        );
        more.type = "button";
        more.dataset.editorAction = "load-more";
        assignPath(more, path);
        body.append(more);
      }
      body.append(addRow(path, "array"));
    } else {
      for (const childKey of orderedObjectKeys(current)) {
        body.append(
          renderValue(
            current[childKey],
            [...path, childKey],
            childKey,
            "object",
            depth + 1,
          ),
        );
      }
      body.append(addRow(path, "object"));
    }
    details.append(body);
  };

  details.addEventListener("toggle", () => {
    if (details.open) {
      state.openPaths.add(keyForOpen);
      renderBody();
    } else {
      state.openPaths.delete(keyForOpen);
    }
  });
  if (details.open) {
    renderBody();
  }
  return details;
}

function renderValue(value, path, key, parentKind, depth = 0, root = false) {
  const kind = valueKind(value);
  if (kind === "object" || kind === "array") {
    return containerNode(value, path, key, parentKind, depth, root);
  }
  return primitiveRow(value, path, key, parentKind);
}

function guidedField(label, value, path) {
  const row = createElement("label", "guided-field");
  row.append(createElement("span", "guided-label", label));
  row.append(primitiveEditor(value ?? "", path, false));
  return row;
}

function guidedActionList(path, title = "실행 명령") {
  const section = createElement("section", "guided-action-list");
  section.append(createElement("h4", "", title));
  const actions = getAtPath(path);
  if (!Array.isArray(actions)) {
    const create = createElement(
      "button",
      "add-button",
      "+ 명령 목록 만들기",
    );
    create.type = "button";
    create.dataset.editorAction = "create-action-list";
    assignPath(create, path);
    section.append(create);
    return section;
  }
  if (actions.length === 0) {
    section.append(createElement("p", "guided-empty", "아직 명령이 없습니다."));
  }
  actions.forEach((action, index) => {
    section.append(
      renderValue(action, [...path, index], index, "array", 0),
    );
  });
  section.append(addRow(path, "array"));
  return section;
}

function guidedCondition(path) {
  const condition = getAtPath(path);
  const section = createElement("section", "guided-condition");
  section.append(createElement("h4", "", "표시 조건"));
  if (!condition || typeof condition !== "object" || Array.isArray(condition)) {
    const create = createElement("button", "add-button", "+ 조건 추가");
    create.type = "button";
    create.dataset.editorAction = "add-condition";
    assignPath(create, path);
    section.append(create);
    return section;
  }
  section.append(renderValue(condition, path, "condition", "object", 0));
  return section;
}

function guidedEventPages(path, kind = "interaction") {
  const section = createElement("section", "guided-event-pages");
  const header = createElement("header", "guided-card-header");
  const heading = createElement("div");
  heading.append(
    createElement("h4", "", "조건부 이벤트 페이지"),
    createElement(
      "p",
      "",
      "아래쪽 페이지가 우선입니다. 조건에 맞는 마지막 페이지의 안내와 명령을 실행합니다.",
    ),
  );
  const add = createElement("button", "add-button", "+ 이벤트 페이지");
  add.type = "button";
  add.dataset.editorAction = "add-event-page";
  add.dataset.eventPageKind = kind;
  assignPath(add, path);
  header.append(heading, add);
  section.append(header);

  const pages = getAtPath(path);
  if (!Array.isArray(pages) || pages.length === 0) {
    section.append(
      createElement(
        "p",
        "guided-empty",
        "페이지가 없으면 위의 기본 실행 명령을 사용합니다.",
      ),
    );
    return section;
  }
  pages.forEach((page, index) => {
    const pagePath = [...path, index];
    const card = createElement("section", "guided-card event-page-card");
    const cardHeader = createElement("header", "guided-card-header");
    cardHeader.append(
      createElement(
        "h4",
        "",
        `Page ${index + 1} · ${page.id || "ID 없음"}`,
      ),
      deleteButton(pagePath, false),
    );
    const fields = createElement("div", "guided-field-grid");
    fields.append(guidedField("페이지 ID", page.id || "", [...pagePath, "id"]));
    if (kind === "trigger") {
      fields.append(
        guidedField(
          "한 번만 실행",
          page.once ?? getAtPath(path.slice(0, -1))?.once ?? false,
          [...pagePath, "once"],
        ),
        guidedField(
          "Cooldown",
          page.cooldown ?? getAtPath(path.slice(0, -1))?.cooldown ?? 0,
          [...pagePath, "cooldown"],
        ),
      );
    } else {
      fields.append(
        guidedField(
          "입력 action",
          page.input || getAtPath(path.slice(0, -1))?.input || "interact",
          [...pagePath, "input"],
        ),
        guidedField(
          "범위",
          page.range ?? getAtPath(path.slice(0, -1))?.range ?? 70,
          [...pagePath, "range"],
        ),
        guidedField(
          "안내 문장 키",
          page.prompt_key || "",
          [...pagePath, "prompt_key"],
        ),
      );
    }
    card.append(
      cardHeader,
      fields,
      guidedCondition([...pagePath, "condition"]),
      guidedActionList([...pagePath, "actions"], "페이지 실행 명령"),
    );
    section.append(card);
  });
  return section;
}

function guidedDialogueEditor() {
  const root = createElement("div", "guided-editor dialogue-guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "간편 대화 편집"),
    createElement("h3", "", "노드와 선택지를 순서대로 연결"),
    createElement(
      "p",
      "",
      "문장 키, 선택 조건과 실행 명령을 카드 안에서 편집합니다.",
    ),
  );
  const addNode = createElement("button", "button secondary", "+ 노드");
  addNode.type = "button";
  addNode.dataset.editorAction = "add-dialogue-node";
  assignPath(addNode, ["nodes"]);
  heading.append(title, addNode);
  root.append(heading);

  const nodes = state.draft.nodes || {};
  for (const nodeID of Object.keys(nodes)) {
    const node = nodes[nodeID];
    const card = createElement("section", "guided-card dialogue-node-card");
    const header = createElement("header", "guided-card-header");
    const headerText = createElement("div");
    headerText.append(
      createElement("span", "guided-kicker", "Dialogue Node"),
      createElement("h4", "", nodeID),
    );
    header.append(headerText, deleteButton(["nodes", nodeID]));
    card.append(header);
    const fields = createElement("div", "guided-field-grid");
    if (Object.prototype.hasOwnProperty.call(node, "speaker_key")) {
      fields.append(
        guidedField(
          "화자 문장 키",
          node.speaker_key,
          ["nodes", nodeID, "speaker_key"],
        ),
      );
    }
    if (Object.prototype.hasOwnProperty.call(node, "text_key")) {
      fields.append(
        guidedField(
          "대사 문장 키",
          node.text_key,
          ["nodes", nodeID, "text_key"],
        ),
      );
    } else if (Object.prototype.hasOwnProperty.call(node, "text")) {
      fields.append(
        guidedField("대사", node.text, ["nodes", nodeID, "text"]),
      );
    }
    card.append(fields);
    if (Object.prototype.hasOwnProperty.call(node, "actions")) {
      card.append(guidedActionList(["nodes", nodeID, "actions"], "노드 진입 명령"));
    }

    const choices = Array.isArray(node.choices) ? node.choices : [];
    const choiceHeading = createElement("div", "guided-subheading");
    choiceHeading.append(
      createElement("h4", "", `선택지 ${choices.length}개`),
    );
    const addChoice = createElement("button", "add-button", "+ 선택지");
    addChoice.type = "button";
    addChoice.dataset.editorAction = "add-dialogue-choice";
    assignPath(addChoice, ["nodes", nodeID, "choices"]);
    choiceHeading.append(addChoice);
    card.append(choiceHeading);
    choices.forEach((choice, choiceIndex) => {
      const choicePath = ["nodes", nodeID, "choices", choiceIndex];
      const choiceCard = createElement("div", "guided-choice-card");
      const choiceHeader = createElement("header", "guided-card-header compact");
      choiceHeader.append(
        createElement("strong", "", choice.id || `choice_${choiceIndex + 1}`),
        deleteButton(choicePath),
      );
      choiceCard.append(choiceHeader);
      const choiceFields = createElement("div", "guided-field-grid");
      choiceFields.append(
        guidedField("선택지 ID", choice.id || "", [...choicePath, "id"]),
      );
      if (Object.prototype.hasOwnProperty.call(choice, "text_key")) {
        choiceFields.append(
          guidedField(
            "선택 문장 키",
            choice.text_key,
            [...choicePath, "text_key"],
          ),
        );
      } else {
        choiceFields.append(
          guidedField("선택 문장", choice.text || "", [...choicePath, "text"]),
        );
      }
      choiceFields.append(
        guidedField("다음 노드", choice.next || "", [...choicePath, "next"]),
      );
      choiceCard.append(
        choiceFields,
        guidedCondition([...choicePath, "condition"]),
        guidedActionList([...choicePath, "actions"]),
      );
      card.append(choiceCard);
    });
    root.append(card);
  }
  return root;
}

function guidedCutsceneEditor() {
  const root = createElement("div", "guided-editor cutscene-guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "간편 컷신 편집"),
    createElement("h3", "", "메시지 장면과 실행 명령"),
    createElement(
      "p",
      "",
      "순서대로 표시할 장면을 만들고 진입·완료 명령을 데이터로 연결합니다. 건너뛰어도 남은 장면 명령과 완료 명령은 순서대로 실행됩니다.",
    ),
  );
  const addStep = createElement("button", "button secondary", "+ 장면");
  addStep.type = "button";
  addStep.dataset.editorAction = "add-cutscene-step";
  assignPath(addStep, ["steps"]);
  heading.append(title, addStep);
  root.append(heading);

  const basic = createElement("div", "guided-card guided-field-grid");
  basic.append(
    guidedField("표시 이름", state.draft.name || "", ["name"]),
    guidedField("이름 문장 키", state.draft.name_key || "", ["name_key"]),
    guidedField("기본 배경 Asset", state.draft.background || "", ["background"]),
    guidedField("건너뛰기 허용", state.draft.skippable ?? true, ["skippable"]),
  );
  root.append(basic);

  const steps = Array.isArray(state.draft.steps) ? state.draft.steps : [];
  steps.forEach((step, index) => {
    const path = ["steps", index];
    const card = createElement("section", "guided-card cutscene-step-card");
    const header = createElement("header", "guided-card-header");
    header.append(
      createElement(
        "h4",
        "",
        `장면 ${index + 1} · ${step.id || "ID 없음"}`,
      ),
      deleteButton(path),
    );
    const fields = createElement("div", "guided-field-grid");
    fields.append(
      guidedField("장면 ID", step.id || "", [...path, "id"]),
      guidedField("화자", step.speaker || "", [...path, "speaker"]),
      guidedField("화자 문장 키", step.speaker_key || "", [...path, "speaker_key"]),
      guidedField("문장", step.text || "", [...path, "text"]),
      guidedField("문장 키", step.text_key || "", [...path, "text_key"]),
      guidedField("배경 Asset", step.background || "", [...path, "background"]),
      guidedField("자동 진행(초)", step.duration ?? "", [...path, "duration"]),
    );
    card.append(
      header,
      fields,
      guidedActionList([...path, "actions"], "장면 진입 명령"),
    );
    root.append(card);
  });
  root.append(guidedActionList(["on_complete"], "컷신 완료 명령"));
  return root;
}

function guidedQuestEditor() {
  const root = createElement("div", "guided-editor quest-guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "간편 퀘스트 편집"),
    createElement("h3", "", "목표 이벤트와 완료 보상"),
    createElement(
      "p",
      "",
      "목표마다 받을 이벤트·필요 횟수를 정하고 완료 명령을 연결합니다.",
    ),
  );
  const addObjective = createElement("button", "button secondary", "+ 목표");
  addObjective.type = "button";
  addObjective.dataset.editorAction = "add-quest-objective";
  assignPath(addObjective, ["objectives"]);
  heading.append(title, addObjective);
  root.append(heading);

  const basic = createElement("div", "guided-card guided-field-grid");
  basic.append(
    guidedField("이름 문장 키", state.draft.name_key || "", ["name_key"]),
    guidedField(
      "설명 문장 키",
      state.draft.description_key || "",
      ["description_key"],
    ),
  );
  root.append(basic);

  const objectives = Array.isArray(state.draft.objectives)
    ? state.draft.objectives
    : [];
  objectives.forEach((objective, index) => {
    const path = ["objectives", index];
    const card = createElement("section", "guided-card");
    const header = createElement("header", "guided-card-header");
    header.append(
      createElement("h4", "", objective.id || `objective_${index + 1}`),
      deleteButton(path),
    );
    const fields = createElement("div", "guided-field-grid");
    fields.append(
      guidedField("목표 ID", objective.id || "", [...path, "id"]),
      guidedField("받을 이벤트", objective.event || "", [...path, "event"]),
      guidedField("필요 횟수", objective.count ?? 1, [...path, "count"]),
    );
    card.append(header, fields);
    if (objective.where && typeof objective.where === "object") {
      card.append(
        renderValue(objective.where, [...path, "where"], "이벤트 필터", "object"),
      );
    }
    root.append(card);
  });
  root.append(guidedActionList(["on_complete"], "완료 보상과 후속 명령"));
  return root;
}

function guidedActorEditor() {
  const root = createElement("div", "guided-editor actor-guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "간편 상호작용 편집"),
    createElement("h3", "", "NPC가 실행할 명령"),
    createElement(
      "p",
      "",
      "플레이어가 상호작용했을 때 대화·상점·퀘스트 명령을 순서대로 실행합니다.",
    ),
  );
  heading.append(title);
  root.append(heading);
  const path = ["components", "rpg.interactable"];
  const interactable = getAtPath(path);
  if (!interactable || typeof interactable !== "object") {
    const create = createElement(
      "button",
      "button secondary",
      "+ NPC 상호작용 추가",
    );
    create.type = "button";
    create.dataset.editorAction = "ensure-interactable";
    assignPath(create, path);
    root.append(create);
  } else {
    const fields = createElement("div", "guided-card guided-field-grid");
    fields.append(
      guidedField("입력 action", interactable.input || "interact", [...path, "input"]),
      guidedField("범위", interactable.range ?? 70, [...path, "range"]),
      guidedField(
        "안내 문장 키",
        interactable.prompt_key || "",
        [...path, "prompt_key"],
      ),
    );
    root.append(
      fields,
      guidedActionList([...path, "actions"]),
      guidedEventPages([...path, "pages"]),
    );
  }

  const battlerPath = ["components", "rpg.turn_battler"];
  const battler = getAtPath(battlerPath);
  if (battler && typeof battler === "object") {
    const section = createElement("section", "guided-card");
    const header = createElement("header", "guided-card-header");
    header.append(createElement("h4", "", "턴제 전투 스킬"));
    const add = createElement("button", "add-button", "+ 스킬");
    add.type = "button";
    add.dataset.editorAction = "add-battler-skill";
    assignPath(add, [...battlerPath, "skills"]);
    header.append(add);
    section.append(header);
    const skills = Array.isArray(battler.skills) ? battler.skills : [];
    if (skills.length === 0) {
      section.append(createElement("p", "guided-empty", "전투 스킬이 없습니다."));
    }
    skills.forEach((skillID, index) => {
      const skillPath = [...battlerPath, "skills", index];
      const row = createElement("div", "guided-choice-card guided-card-header compact");
      const options = sortedNodes()
        .filter((node) => node.kind === "turn_skill")
        .map((node) => ({ value: node.id, label: node.id }));
      row.append(
        semanticSelect(skillID, skillPath, options),
        deleteButton(skillPath),
      );
      section.append(row);
    });
    root.append(section);
  }
  return root;
}

function guidedTurnSkillEditor() {
  const root = createElement("div", "guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "턴제 스킬"),
    createElement("h3", "", "효과와 위력"),
    createElement(
      "p",
      "",
      "피해 스킬은 적을, 회복 스킬은 자신을 대상으로 사용합니다.",
    ),
  );
  heading.append(title);
  const fields = createElement("div", "guided-card guided-field-grid");
  fields.append(
    guidedField("표시 이름", state.draft.name || "", ["name"]),
    guidedField("이름 문장 키", state.draft.name_key || "", ["name_key"]),
    guidedField("효과", state.draft.effect || "damage", ["effect"]),
    guidedField("대상", state.draft.target || "enemy", ["target"]),
    guidedField("위력", state.draft.power ?? 1, ["power"]),
  );
  root.append(heading, fields);
  return root;
}

function guidedTurnBattleEditor() {
  const root = createElement("div", "guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "턴제 전투"),
    createElement("h3", "", "적 편성과 결과 명령"),
    createElement(
      "p",
      "",
      "전투에 등장할 battler actor와 승리·도주·패배 뒤 실행할 명령을 연결합니다.",
    ),
  );
  const addEnemy = createElement("button", "button secondary", "+ 적");
  addEnemy.type = "button";
  addEnemy.dataset.editorAction = "add-turn-battle-enemy";
  assignPath(addEnemy, ["enemies"]);
  heading.append(title, addEnemy);
  root.append(heading);

  const basic = createElement("div", "guided-card guided-field-grid");
  basic.append(
    guidedField("표시 이름", state.draft.name || "", ["name"]),
    guidedField("이름 문장 키", state.draft.name_key || "", ["name_key"]),
    guidedField("도주 허용", state.draft.allow_escape ?? false, ["allow_escape"]),
    guidedField("반복 가능", state.draft.repeatable ?? false, ["repeatable"]),
  );
  root.append(basic);

  const enemies = Array.isArray(state.draft.enemies)
    ? state.draft.enemies
    : [];
  enemies.forEach((enemy, index) => {
    const path = ["enemies", index];
    const card = createElement("section", "guided-card");
    const header = createElement("header", "guided-card-header");
    header.append(
      createElement("h4", "", enemy.id || `enemy_${index + 1}`),
      deleteButton(path),
    );
    const fields = createElement("div", "guided-field-grid");
    fields.append(
      guidedField("전투 내 ID", enemy.id || "", [...path, "id"]),
      guidedField("Actor", enemy.actor || "", [...path, "actor"]),
    );
    card.append(header, fields);
    root.append(card);
  });
  root.append(
    guidedActionList(["on_start"], "전투 시작 명령"),
    guidedActionList(["on_victory"], "승리 명령"),
    guidedActionList(["on_escape"], "도주 명령"),
    guidedActionList(["on_defeat"], "패배 명령"),
  );
  return root;
}

function optionalMapProperty(value) {
  const text = String(value || "").trim();
  return text === "" ? null : text;
}

function mapObjectProperties(object) {
  switch (object.class) {
    case "spawn":
      return {
        actor: optionalMapProperty(object.actor),
        id:
          object.properties?.id !== undefined ||
          object.spawn_id !== object.name
            ? optionalMapProperty(object.spawn_id)
            : null,
        tags: optionalMapProperty(object.tags),
      };
    case "spawn_point":
      return {
        id:
          object.properties?.id !== undefined ||
          object.spawn_id !== object.name
            ? optionalMapProperty(object.spawn_id)
            : null,
      };
    case "portal":
      return {
        actor_tag: optionalMapProperty(object.actor_tag),
        cooldown: String(Number(object.cooldown) || 0),
        target_stage: String(object.target_stage || ""),
        target_spawn: String(object.target_spawn || ""),
      };
    case "trigger":
      return {
        actions: Array.isArray(object.actions)
          ? JSON.stringify(object.actions)
          : null,
        actor_tag: optionalMapProperty(object.actor_tag),
        condition: object.condition
          ? JSON.stringify(object.condition)
          : null,
        cooldown: String(Number(object.cooldown) || 0),
        once: object.once ? "true" : "false",
        pages: Array.isArray(object.pages) && object.pages.length > 0
          ? JSON.stringify(object.pages)
          : null,
      };
    case "region":
      return {
        actor_tag: optionalMapProperty(object.actor_tag),
        condition: object.condition
          ? JSON.stringify(object.condition)
          : null,
        id:
          object.properties?.id !== undefined ||
          object.spawn_id !== object.name
            ? optionalMapProperty(object.spawn_id)
            : null,
        on_enter: Array.isArray(object.on_enter) &&
          object.on_enter.length > 0
          ? JSON.stringify(object.on_enter)
          : null,
        on_exit: Array.isArray(object.on_exit) &&
          object.on_exit.length > 0
          ? JSON.stringify(object.on_exit)
          : null,
      };
    default:
      return {};
  }
}

function mapWorldPageProperties(mapDraft) {
  const pages = Array.isArray(mapDraft?.world_pages)
    ? mapDraft.world_pages
    : [];
  return {
    world_pages: pages.length > 0 ? JSON.stringify(pages) : null,
  };
}

async function saveMapWorldPages(button) {
  if (!state.mapDraft || !state.mapSource || !state.mapRevision) {
    toast("저장할 TMX 맵 상태를 찾을 수 없습니다.", "error");
    return;
  }
  if (
    stableText(state.mapDraft.world_pages || []) ===
    stableText(state.originalMapDraft?.world_pages || [])
  ) {
    toast("적용할 월드 페이지 변경이 없습니다.");
    return;
  }
  const previousText = button.textContent;
  button.disabled = true;
  button.textContent = "월드 상태 적용 중…";
  try {
    const result = await apiJSON("/api/map", {
      method: "POST",
      headers: { "If-Match": state.mapRevision },
      body: {
        source: state.mapSource,
        object_id: 0,
        class: "map",
        properties: mapWorldPageProperties(state.mapDraft),
      },
    });
    const hydrated = hydrateMapResult(result.map);
    state.mapRevision = String(result.map?.revision || "");
    state.mapDraft = hydrated;
    state.originalMapDraft = deepClone(hydrated);
    updateDirtyFromDraft();
    await refreshGraph(false, { notify: false });
    await selectContent(state.selectedID, {
      skipDirtyCheck: true,
      force: true,
    });
    const warnings = Array.isArray(result?.warnings)
      ? result.warnings.filter(Boolean)
      : [];
    toast(
      warnings.length > 0
        ? `월드 페이지는 반영됐습니다. ${warnings.join(" / ")}`
        : "시간·조건별 맵 상태를 TMX와 실행 화면에 반영했습니다.",
      warnings.length > 0 ? "" : "success",
    );
    requestScreenshotSoon(80);
  } catch (error) {
    toast(`월드 페이지 저장 실패: ${errorMessage(error)}`, "error");
  } finally {
    button.disabled = false;
    button.textContent = previousText;
  }
}

async function saveMapObject(index, button) {
  const object = state.mapDraft?.objects?.[index];
  if (!object || !state.mapSource || !state.mapRevision) {
    toast("저장할 TMX object를 찾을 수 없습니다.", "error");
    return;
  }
  const previousText = button.textContent;
  button.disabled = true;
  button.textContent = "맵 적용 중…";
  try {
    const originals = new Map(
      (state.originalMapDraft?.objects || []).map((entry) => [
        `${entry.class}/${entry.id}`,
        entry,
      ]),
    );
    const changed = state.mapDraft.objects.filter((entry) => {
      const original = originals.get(`${entry.class}/${entry.id}`);
      return !original || stableText(entry) !== stableText(original);
    });
    if (changed.length === 0) {
      toast("적용할 맵 변경이 없습니다.");
      return;
    }
    let revision = state.mapRevision;
    let result = null;
    const warnings = [];
    for (const entry of changed) {
      result = await apiJSON("/api/map", {
        method: "POST",
        headers: { "If-Match": revision },
        body: {
          source: state.mapSource,
          object_id: entry.id,
          class: entry.class,
          x: Number(entry.x),
          y: Number(entry.y),
          width: Number(entry.width),
          height: Number(entry.height),
          properties: mapObjectProperties(entry),
        },
      });
      revision = String(result.map?.revision || "");
      state.mapRevision = revision;
      if (Array.isArray(result?.warnings)) {
        warnings.push(...result.warnings.filter(Boolean));
      }
    }
    const hydrated = hydrateMapResult(result.map);
    state.mapRevision = revision;
    state.mapDraft = hydrated;
    state.originalMapDraft = deepClone(hydrated);
    updateDirtyFromDraft();
    await refreshGraph(false, { notify: false });
    await selectContent(state.selectedID, {
      skipDirtyCheck: true,
      force: true,
    });
    toast(
      warnings.length > 0
        ? `맵은 반영됐습니다. ${warnings.join(" / ")}`
        : "TMX를 저장하고 generated stage와 게임 화면을 갱신했습니다.",
      warnings.length > 0 ? "" : "success",
    );
    requestScreenshotSoon(80);
  } catch (error) {
    toast(`맵 저장 실패: ${errorMessage(error)}`, "error");
  } finally {
    button.disabled = false;
    button.textContent = previousText;
  }
}

function guidedWorldPages() {
  const section = createElement("section", "guided-card world-pages-card");
  const header = createElement("header", "guided-card-header");
  const heading = createElement("div");
  heading.append(
    createElement("span", "guided-kicker", "시간·조건별 맵 상태"),
    createElement("h4", "", "월드 페이지"),
    createElement(
      "p",
      "",
      "조건에 맞는 마지막 페이지가 적용됩니다. 색조·타일 레이어와 진입·이탈 명령을 한곳에서 편집합니다.",
    ),
  );
  const controls = createElement("div", "guided-card-header compact");
  const add = createElement("button", "add-button", "+ 월드 페이지");
  add.type = "button";
  add.dataset.editorAction = "add-world-page";
  assignPath(add, ["@map", "world_pages"]);
  const save = createElement("button", "button secondary", "월드 상태 적용");
  save.type = "button";
  save.dataset.editorAction = "save-map-world-pages";
  assignPath(save, ["@map", "world_pages"]);
  controls.append(add, save);
  header.append(heading, controls);
  section.append(header);

  const pages = Array.isArray(state.mapDraft?.world_pages)
    ? state.mapDraft.world_pages
    : [];
  if (pages.length === 0) {
    section.append(
      createElement(
        "p",
        "guided-empty",
        "월드 페이지가 없으면 맵은 기본 색조와 레이어 상태를 유지합니다.",
      ),
    );
    return section;
  }
  pages.forEach((page, index) => {
    const path = ["@map", "world_pages", index];
    const card = createElement("section", "guided-card event-page-card");
    const cardHeader = createElement("header", "guided-card-header");
    cardHeader.append(
      createElement(
        "h4",
        "",
        `Page ${index + 1} · ${page.id || "ID 없음"}`,
      ),
      deleteButton(path),
    );
    const fields = createElement("div", "guided-field-grid");
    fields.append(
      guidedField("페이지 ID", page.id || "", [...path, "id"]),
      guidedField("Tint R", page.tint[0], [...path, "tint", 0]),
      guidedField("Tint G", page.tint[1], [...path, "tint", 1]),
      guidedField("Tint B", page.tint[2], [...path, "tint", 2]),
      guidedField("Tint A", page.tint[3], [...path, "tint", 3]),
    );
    const layers = createElement("section", "guided-action-list");
    const layerHeader = createElement("header", "guided-card-header compact");
    layerHeader.append(
      createElement("h4", "", "타일 레이어 표시"),
    );
    const addLayer = createElement("button", "add-button", "+ 레이어");
    addLayer.type = "button";
    addLayer.dataset.editorAction = "add-world-layer";
    assignPath(addLayer, [...path, "layers"]);
    layerHeader.append(addLayer);
    layers.append(layerHeader);
    page.layers.forEach((layer, layerIndex) => {
      const layerPath = [...path, "layers", layerIndex];
      const row = createElement(
        "div",
        "guided-choice-card guided-card-header compact",
      );
      row.append(
        guidedField("Layer ID", layer.id || "", [...layerPath, "id"]),
        guidedField(
          "표시",
          layer.visible ?? true,
          [...layerPath, "visible"],
        ),
        deleteButton(layerPath),
      );
      layers.append(row);
    });
    card.append(
      cardHeader,
      fields,
      guidedCondition([...path, "condition"]),
      layers,
      guidedActionList([...path, "on_enter"], "페이지 진입 명령"),
      guidedActionList([...path, "on_exit"], "페이지 이탈 명령"),
    );
    section.append(card);
  });
  return section;
}

function guidedStageInspector() {
  const root = createElement("div", "guided-editor stage-guided-editor");
  const heading = createElement("div", "guided-heading");
  const title = createElement("div");
  title.append(
    createElement("span", "guided-kicker", "맵 연결 검사"),
    createElement("h3", "", "배치와 이동 연결"),
    createElement(
      "p",
      "",
      state.mapDraft
        ? "TMX actor·spawn 좌표, trigger·region 명령과 portal 목적지를 수정하면 generated stage와 실행 화면을 함께 갱신합니다."
        : "spawn, trigger, region과 portal의 ID 연결을 검사합니다.",
    ),
  );
  heading.append(title);
  root.append(heading);
  const summary = createElement("div", "stage-summary-grid");
  const groups = [
    ["Spawn", state.draft.spawn_points || []],
    ["Trigger", state.draft.triggers || []],
    ["Region", state.draft.world_state?.regions || []],
    ["Portal", state.draft.portals || []],
    ["Actor", state.draft.spawns || []],
  ];
  for (const [label, entries] of groups) {
    const card = createElement("section", "stage-summary-card");
    card.append(
      createElement("span", "guided-kicker", label),
      createElement("strong", "", `${entries.length}개`),
    );
    const list = createElement("ul", "");
    entries.forEach((entry) => {
      let detail = entry.id || entry.actor || "이름 없음";
      if (label === "Portal") {
        detail += ` → ${entry.target_stage || "?"}/${entry.target_spawn || "?"}`;
      } else if (label === "Trigger") {
        detail += ` · 명령 ${Array.isArray(entry.actions) ? entry.actions.length : 0}개`;
      }
      list.append(createElement("li", "", detail));
    });
    card.append(list);
    summary.append(card);
  }
  root.append(summary);
  if (!state.mapDraft) {
    return root;
  }
  root.append(guidedWorldPages());

  state.mapDraft.objects.forEach((object, index) => {
    const path = ["@map", "objects", index];
    const card = createElement("section", "guided-card map-object-card");
    const header = createElement("header", "guided-card-header");
    const headingText = createElement("div");
    headingText.append(
      createElement("span", "guided-kicker", object.class),
      createElement("h4", "", `${object.name || "이름 없음"} · #${object.id}`),
    );
    const save = createElement(
      "button",
      "button secondary",
      "맵 변경 적용",
    );
    save.type = "button";
    save.dataset.editorAction = "save-map-object";
    assignPath(save, ["@map", "objects", index]);
    header.append(headingText, save);
    const geometry = createElement("div", "guided-field-grid map-geometry-grid");
    geometry.append(
      guidedField("X", object.x, [...path, "x"]),
      guidedField("Y", object.y, [...path, "y"]),
      guidedField("너비", object.width, [...path, "width"]),
      guidedField("높이", object.height, [...path, "height"]),
    );
    card.append(header, geometry);
    const fields = createElement("div", "guided-field-grid map-property-grid");
    if (object.class === "spawn") {
      fields.append(
        guidedField("Actor 콘텐츠", object.actor, [...path, "actor"]),
        guidedField("Entity ID", object.spawn_id, [...path, "spawn_id"]),
        guidedField("Tags", object.tags, [...path, "tags"]),
      );
    } else if (object.class === "spawn_point") {
      fields.append(
        guidedField("Spawn ID", object.spawn_id, [...path, "spawn_id"]),
      );
    } else if (object.class === "portal") {
      fields.append(
        guidedField(
          "목적지 Stage",
          object.target_stage,
          [...path, "target_stage"],
        ),
        guidedField(
          "목적지 Spawn",
          object.target_spawn,
          [...path, "target_spawn"],
        ),
        guidedField("Actor Tag", object.actor_tag, [...path, "actor_tag"]),
        guidedField("Cooldown", object.cooldown, [...path, "cooldown"]),
      );
    } else if (object.class === "trigger") {
      fields.append(
        guidedField("Actor Tag", object.actor_tag, [...path, "actor_tag"]),
        guidedField("Cooldown", object.cooldown, [...path, "cooldown"]),
        guidedField("한 번만 실행", object.once, [...path, "once"]),
      );
    } else if (object.class === "region") {
      fields.append(
        guidedField("Region ID", object.spawn_id, [...path, "spawn_id"]),
        guidedField("Actor Tag", object.actor_tag, [...path, "actor_tag"]),
      );
    }
    if (fields.childElementCount > 0) {
      card.append(fields);
    }
    if (object.class === "trigger") {
      card.append(
        guidedCondition([...path, "condition"]),
        guidedActionList([...path, "actions"], "Trigger 실행 명령"),
        guidedEventPages([...path, "pages"], "trigger"),
      );
    } else if (object.class === "region") {
      card.append(
        guidedCondition([...path, "condition"]),
        guidedActionList([...path, "on_enter"], "Region 진입 명령"),
        guidedActionList([...path, "on_exit"], "Region 이탈 명령"),
      );
    }
    root.append(card);
  });
  return root;
}

function renderGuidedEditor() {
  switch (state.draft?.kind) {
    case "cutscene":
      return guidedCutsceneEditor();
    case "dialogue":
      return guidedDialogueEditor();
    case "quest":
      return guidedQuestEditor();
    case "actor":
      return guidedActorEditor();
    case "turn_skill":
      return guidedTurnSkillEditor();
    case "turn_battle":
      return guidedTurnBattleEditor();
    case "stage":
      return guidedStageInspector();
    default:
      return null;
  }
}

function renderStructuredForm() {
  const container = $("#structured-form");
  container.replaceChildren();
  if (!state.draft) {
    return;
  }
  const guided = renderGuidedEditor();
  if (guided) {
    const advanced = createElement("details", "schema-advanced");
    const summary = createElement("summary", "", "전체 스키마 필드 (고급)");
    const help = createElement(
      "p",
      "guided-empty",
      "간편 화면에 없는 모든 필드를 직접 편집할 때만 펼치세요.",
    );
    advanced.append(
      summary,
      help,
      renderValue(state.draft, [], "definition", "object", 0, true),
    );
    container.append(guided, advanced);
  } else {
    container.append(
      renderValue(state.draft, [], "definition", "object", 0, true),
    );
  }
}

function markDraftChanged({ structural = false } = {}) {
  updateDirtyFromDraft();
  showValidation("neutral", "draft가 변경되었습니다. 다시 검증하세요.");
  if (state.activeTab !== "json") {
    state.jsonDirty = false;
  }
  if (structural) {
    renderStructuredForm();
  }
}

function updatePrimitiveFromInput(input) {
  const path = readPath(input);
  const schemaRole = input.dataset.schemaRole || "";
  if (schemaRole === "action-type" || schemaRole === "condition-type") {
    const parentPath = path.slice(0, -1);
    const previous = getAtPath(parentPath);
    const next = schemaRole === "action-type"
      ? actionPreset(input.value)
      : conditionPreset(input.value);
    if (
      previous &&
      Object.keys(previous).length > 1 &&
      !window.confirm(
        "종류를 바꾸면 이 명령/조건의 기존 세부 필드가 새 기본값으로 바뀝니다. 계속할까요?",
      )
    ) {
      input.value = String(previous.type || "");
      return;
    }
    setAtPath(parentPath, next);
    markDraftChanged({ structural: true });
    return;
  }
  const type = input.dataset.valueType;
  let value;
  if (type === "boolean") {
    value = input.checked;
    const text = $("span", input.parentElement);
    if (text) {
      text.textContent = value ? "true" : "false";
    }
  } else if (type === "number") {
    value = input.value === "" ? 0 : Number(input.value);
    if (!Number.isFinite(value)) {
      return;
    }
  } else if (type === "null") {
    return;
  } else {
    value = input.value;
  }
  setAtPath(path, value);
  markDraftChanged();
}

function valueHasContent(value) {
  if (Array.isArray(value)) {
    return value.length > 0;
  }
  if (value && typeof value === "object") {
    return Object.keys(value).length > 0;
  }
  return value !== "" && value !== false && value !== 0 && value !== null;
}

function changeValueType(select) {
  const path = readPath(select);
  const current = getAtPath(path);
  const nextType = select.value;
  if (nextType === valueKind(current)) {
    return;
  }
  if (
    valueHasContent(current) &&
    !window.confirm("값의 형식을 바꾸면 기존 내용이 사라집니다. 계속할까요?")
  ) {
    select.value = valueKind(current);
    return;
  }
  setAtPath(path, defaultForType(nextType));
  markDraftChanged({ structural: true });
}

function deleteAtPath(path) {
  if (path.length === 0 || rootFieldLocked(path)) {
    return;
  }
  const parentPath = path.slice(0, -1);
  const parent = getAtPath(parentPath);
  const key = path[path.length - 1];
  if (
    !window.confirm(
      `${Array.isArray(parent) ? `#${Number(key) + 1}` : String(key)} 값을 삭제할까요?`,
    )
  ) {
    return;
  }
  if (Array.isArray(parent)) {
    parent.splice(Number(key), 1);
  } else if (parent && typeof parent === "object") {
    delete parent[key];
  }
  markDraftChanged({ structural: true });
}

function renameAtPath(path) {
  if (path.length === 0 || rootFieldLocked(path)) {
    return;
  }
  const parent = getAtPath(path.slice(0, -1));
  if (!parent || Array.isArray(parent) || typeof parent !== "object") {
    return;
  }
  const oldKey = String(path[path.length - 1]);
  const newKey = window.prompt("새 필드 이름", oldKey);
  if (newKey === null || newKey === oldKey) {
    return;
  }
  if (!newKey.trim()) {
    toast("필드 이름은 비워둘 수 없습니다.", "error");
    return;
  }
  if (Object.prototype.hasOwnProperty.call(parent, newKey)) {
    toast(`이미 '${newKey}' 필드가 있습니다.`, "error");
    return;
  }
  parent[newKey] = parent[oldKey];
  delete parent[oldKey];
  markDraftChanged({ structural: true });
}

function addAtPath(button) {
  const path = readPath(button);
  const target = getAtPath(path);
  const row = button.closest(".add-row");
  const type = $('[data-editor-role="new-type"]', row)?.value || "string";
  if (Array.isArray(target)) {
    target.push(defaultForType(type));
  } else if (target && typeof target === "object") {
    const keyInput = $('[data-editor-role="new-key"]', row);
    const key = keyInput?.value.trim() || "";
    if (!key) {
      toast("추가할 필드 이름을 입력하세요.", "error");
      keyInput?.focus();
      return;
    }
    if (Object.prototype.hasOwnProperty.call(target, key)) {
      toast(`이미 '${key}' 필드가 있습니다.`, "error");
      keyInput?.focus();
      return;
    }
    target[key] = defaultForType(type);
  } else {
    return;
  }
  state.openPaths.add(pathKey(path));
  markDraftChanged({ structural: true });
}

function addActionAtPath(button) {
  const path = readPath(button);
  const target = getAtPath(path);
  if (!Array.isArray(target)) {
    toast("명령을 추가할 배열을 찾을 수 없습니다.", "error");
    return;
  }
  const row = button.closest(".add-row");
  const type = $('[data-editor-role="new-action-type"]', row)?.value;
  if (!type) {
    toast("추가할 명령 종류를 선택하세요.", "error");
    return;
  }
  target.push(actionPreset(type));
  state.openPaths.add(pathKey([...path, target.length - 1]));
  markDraftChanged({ structural: true });
}

function createActionListAtPath(path) {
  const parent = getAtPath(path.slice(0, -1));
  if (!parent || typeof parent !== "object") {
    toast("명령 목록을 만들 위치를 찾을 수 없습니다.", "error");
    return;
  }
  setAtPath(path, []);
  markDraftChanged({ structural: true });
}

function addConditionAtPath(path) {
  const parent = getAtPath(path.slice(0, -1));
  if (!parent || typeof parent !== "object") {
    toast("조건을 추가할 위치를 찾을 수 없습니다.", "error");
    return;
  }
  setAtPath(path, conditionPreset("always"));
  state.openPaths.add(pathKey(path));
  markDraftChanged({ structural: true });
}

function safeAuthoringID(raw) {
  return String(raw || "").trim().replace(/[^A-Za-z0-9_.-]+/g, "_");
}

function addDialogueNode(path) {
  const nodes = getAtPath(path);
  if (!nodes || Array.isArray(nodes) || typeof nodes !== "object") {
    toast("dialogue nodes 객체를 찾을 수 없습니다.", "error");
    return;
  }
  const proposed = window.prompt("새 노드 ID", "new_node");
  if (proposed === null) {
    return;
  }
  const nodeID = safeAuthoringID(proposed);
  if (!nodeID) {
    toast("노드 ID를 입력하세요.", "error");
    return;
  }
  if (Object.prototype.hasOwnProperty.call(nodes, nodeID)) {
    toast(`이미 '${nodeID}' 노드가 있습니다.`, "error");
    return;
  }
  nodes[nodeID] = {
    text: "새 대사",
    choices: [],
  };
  if (!state.draft.start) {
    state.draft.start = nodeID;
  }
  markDraftChanged({ structural: true });
}

function addDialogueChoice(path) {
  let choices = getAtPath(path);
  if (!Array.isArray(choices)) {
    const parent = getAtPath(path.slice(0, -1));
    if (!parent || typeof parent !== "object") {
      toast("선택지를 추가할 노드를 찾을 수 없습니다.", "error");
      return;
    }
    choices = [];
    setAtPath(path, choices);
  }
  const used = new Set(choices.map((choice) => choice?.id));
  let sequence = choices.length + 1;
  while (used.has(`choice_${sequence}`)) {
    sequence++;
  }
  choices.push({
    id: `choice_${sequence}`,
    text: "새 선택지",
    condition: conditionPreset("always"),
    actions: [],
  });
  markDraftChanged({ structural: true });
}

function addQuestObjective(path) {
  let objectives = getAtPath(path);
  if (!Array.isArray(objectives)) {
    objectives = [];
    setAtPath(path, objectives);
  }
  const used = new Set(objectives.map((objective) => objective?.id));
  let sequence = objectives.length + 1;
  while (used.has(`objective_${sequence}`)) {
    sequence++;
  }
  const actor =
    graphNodes().find((node) => node.id === "actor.slime")?.id ||
    firstContentID("actor");
  objectives.push({
    id: `objective_${sequence}`,
    event: "actor.killed",
    count: 1,
    where: actor ? { actor_id: actor } : {},
  });
  markDraftChanged({ structural: true });
}

function addTurnBattleEnemy(path) {
  let enemies = getAtPath(path);
  if (!Array.isArray(enemies)) {
    enemies = [];
    setAtPath(path, enemies);
  }
  const used = new Set(enemies.map((enemy) => enemy?.id));
  let sequence = enemies.length + 1;
  while (used.has(`enemy_${sequence}`)) {
    sequence++;
  }
  enemies.push({
    id: `enemy_${sequence}`,
    actor: enemies[0]?.actor || firstContentID("actor"),
  });
  markDraftChanged({ structural: true });
}

function addCutsceneStep(path) {
  let steps = getAtPath(path);
  if (!Array.isArray(steps)) {
    steps = [];
    setAtPath(path, steps);
  }
  const used = new Set(steps.map((step) => step?.id));
  let sequence = steps.length + 1;
  while (used.has(`step_${sequence}`)) {
    sequence++;
  }
  steps.push({
    id: `step_${sequence}`,
    text: "새 컷신 문장을 입력하세요.",
    actions: [],
  });
  state.openPaths.add(pathKey([...path, steps.length - 1]));
  markDraftChanged({ structural: true });
}

function addBattlerSkill(path) {
  let skills = getAtPath(path);
  if (!Array.isArray(skills)) {
    skills = [];
    setAtPath(path, skills);
  }
  const skill = sortedNodes().find(
    (node) => node.kind === "turn_skill" && !skills.includes(node.id),
  );
  if (!skill) {
    toast("추가할 수 있는 턴제 스킬이 없습니다.", "error");
    return;
  }
  skills.push(skill.id);
  markDraftChanged({ structural: true });
}

function addEventPage(path, kind = "interaction") {
  const owner = getAtPath(path.slice(0, -1));
  if (!owner || typeof owner !== "object") {
    toast("이벤트 페이지를 추가할 상호작용을 찾을 수 없습니다.", "error");
    return;
  }
  let pages = getAtPath(path);
  if (!Array.isArray(pages)) {
    pages = [];
    setAtPath(path, pages);
  }
  const used = new Set(pages.map((page) => page?.id));
  let sequence = pages.length + 1;
  while (used.has(`page_${sequence}`)) {
    sequence++;
  }
  const first = pages.length === 0;
  const page = {
    id: first ? "default" : `page_${sequence}`,
    actions: first && Array.isArray(owner.actions)
      ? deepClone(owner.actions)
      : [actionPreset("show_notice")],
  };
  if (kind === "trigger") {
    page.once = owner.once ?? false;
    page.cooldown = owner.cooldown ?? 0;
  } else {
    page.input = owner.input || "interact";
    page.range = owner.range ?? 70;
    page.prompt_key = owner.prompt_key || "interaction.talk";
  }
  pages.push(page);
  if (first) {
    delete owner.actions;
  }
  state.openPaths.add(pathKey([...path, pages.length - 1]));
  markDraftChanged({ structural: true });
}

function addWorldPage(path) {
  let pages = getAtPath(path);
  if (!Array.isArray(pages)) {
    pages = [];
    setAtPath(path, pages);
  }
  const used = new Set(pages.map((page) => page?.id));
  let sequence = pages.length + 1;
  while (used.has(`world_page_${sequence}`)) {
    sequence++;
  }
  pages.push({
    id: `world_page_${sequence}`,
    condition: conditionPreset("always"),
    tint: [0, 0, 0, 0],
    layers: [],
    on_enter: [],
    on_exit: [],
  });
  markDraftChanged({ structural: true });
}

function addWorldLayer(path) {
  let layers = getAtPath(path);
  if (!Array.isArray(layers)) {
    layers = [];
    setAtPath(path, layers);
  }
  const available = Array.isArray(state.draft?.tilemap?.layers)
    ? state.draft.tilemap.layers
    : [];
  const used = new Set(layers.map((layer) => layer?.id));
  const layerID =
    available.find((layer) => !used.has(layer?.id))?.id ||
    `layer_${layers.length + 1}`;
  layers.push({ id: layerID, visible: true });
  markDraftChanged({ structural: true });
}

function ensureInteractable(path) {
  const components = getAtPath(path.slice(0, -1));
  if (!components || typeof components !== "object") {
    toast("actor components 객체를 찾을 수 없습니다.", "error");
    return;
  }
  setAtPath(path, {
    input: "interact",
    range: 70,
    prompt_key: "interaction.talk",
    actions: [],
  });
  markDraftChanged({ structural: true });
}

function loadMore(path) {
  const key = pathKey(path);
  state.arrayLimits.set(key, (state.arrayLimits.get(key) || 120) + 240);
  state.openPaths.add(key);
  renderStructuredForm();
}

function syncJSONFromDraft() {
  if (!state.draft) {
    $("#json-editor").value = "";
    return;
  }
  $("#json-editor").value = JSON.stringify(state.draft, null, 2);
  state.jsonDirty = false;
  setJSONStatus("JSON과 구조 편집 draft가 동기화되었습니다.", "success");
}

function setJSONStatus(message, kind = "") {
  const element = $("#json-status");
  element.textContent = message;
  element.className = `inline-status${kind ? ` ${kind}` : ""}`;
}

function parseJSONEditor({ quiet = false } = {}) {
  let parsed;
  try {
    parsed = JSON.parse($("#json-editor").value);
  } catch (error) {
    setJSONStatus(`JSON 오류: ${error.message}`, "error");
    if (!quiet) {
      toast(`JSON을 적용할 수 없습니다: ${error.message}`, "error");
    }
    return false;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    setJSONStatus("최상위 값은 JSON 객체여야 합니다.", "error");
    if (!quiet) {
      toast("최상위 값은 JSON 객체여야 합니다.", "error");
    }
    return false;
  }
  state.draft = parsed;
  state.jsonDirty = false;
  updateDirtyFromDraft();
  setJSONStatus("올바른 JSON입니다. draft에 적용되었습니다.", "success");
  return true;
}

function currentDraftReady() {
  if (!state.current || !state.draft) {
    toast("먼저 콘텐츠를 선택하세요.", "error");
    return false;
  }
  if (state.activeTab === "json" || state.jsonDirty) {
    return parseJSONEditor();
  }
  return true;
}

function switchTab(tab, { skipJSONParse = false } = {}) {
  if (
    state.activeTab === "json" &&
    tab !== "json" &&
    !skipJSONParse &&
    !parseJSONEditor()
  ) {
    return false;
  }
  if (tab === "json" && state.activeTab !== "json") {
    syncJSONFromDraft();
  }
  if (tab === "form" && state.activeTab === "json") {
    renderStructuredForm();
  }

  state.activeTab = tab;
  for (const button of $$(".editor-tab")) {
    const active = button.dataset.tab === tab;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", active ? "true" : "false");
  }
  $("#form-pane").hidden = tab !== "form";
  $("#json-pane").hidden = tab !== "json";
  $("#relations-pane").hidden = tab !== "relations";
  return true;
}

function renderRelationList(container, edges) {
  container.replaceChildren();
  if (!Array.isArray(edges) || edges.length === 0) {
    container.append(
      createElement("div", "relation-empty", "연결된 콘텐츠가 없습니다."),
    );
    return;
  }
  for (const edge of edges) {
    const button = createElement("button", "relation-item");
    button.type = "button";
    button.dataset.contentId = edge.id;
    button.append(
      createElement("strong", "", edge.id || "unknown"),
      createElement("span", "", edge.path || "참조 경로 없음"),
    );
    container.append(button);
  }
}

function renderRelations() {
  const dependencies = state.current?.dependencies || [];
  const dependents = state.current?.dependents || [];
  $("#dependency-count").textContent = String(dependencies.length);
  $("#dependent-count").textContent = String(dependents.length);
  renderRelationList($("#dependency-list"), dependencies);
  renderRelationList($("#dependent-list"), dependents);
}

function showValidation(kind, message) {
  const element = $("#validation-result");
  element.className = `validation-result ${kind}`;
  element.textContent = message;
}

async function validateCurrent() {
  if (!currentDraftReady()) {
    return;
  }
  const button = $("#validate-content");
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = "검증 중…";
  showValidation("neutral", "전체 Catalog와 현재 World를 기준으로 검증 중입니다.");
  try {
    const result = await apiJSON(
      `/api/content/validate?id=${encodeURIComponent(state.selectedID)}`,
      {
        method: "POST",
        body: { definition: state.draft },
      },
    );
    const total = result?.summary?.total;
    showValidation(
      "success",
      `검증 성공: ${result?.id || state.selectedID}` +
        (total === undefined ? "" : ` · 전체 콘텐츠 ${total}개`),
    );
    toast("현재 draft가 엔진 검증을 통과했습니다.", "success");
  } catch (error) {
    showValidation("error", `검증 실패\n${errorMessage(error)}`);
    toast("콘텐츠 검증에 실패했습니다.", "error");
  } finally {
    button.disabled = false;
    button.textContent = originalText;
  }
}

function applySavedContent(result) {
  const saved = result?.content || {};
  const definition = saved.definition || state.draft;
  state.current = {
    ...state.current,
    ...saved,
    definition,
  };
  state.revision = String(
    result?.revision || saved.revision || state.revision || "",
  );
  state.draft = deepClone(definition);
  state.originalDefinition = deepClone(definition);
  state.dirty = false;
  state.jsonDirty = false;
  state.openPaths = new Set(["[]"]);
  state.arrayLimits = new Map();
  renderEditor();
  if (result?.runtime) {
    const project = {
      ...(state.project || {}),
      runtime: result.runtime,
      world: state.project?.world || {},
    };
    renderProject(project);
  }
}

async function saveCurrent() {
  if (!currentDraftReady()) {
    return;
  }
  if (state.current?.read_only) {
    toast("읽기 전용 콘텐츠는 저장할 수 없습니다.", "error");
    return;
  }
  if (!state.revision) {
    toast(
      "현재 파일 revision이 없습니다. 콘텐츠를 새로고침한 뒤 다시 저장하세요.",
      "error",
    );
    return;
  }

  const button = $("#save-content");
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = "저장 중…";
  showValidation(
    "neutral",
    "revision을 확인하고 파일을 원자적으로 저장한 뒤 런타임을 다시 불러오는 중입니다.",
  );
  try {
    let result;
    try {
      result = await apiJSON(
        `/api/content/save?id=${encodeURIComponent(state.selectedID)}`,
        {
          method: "POST",
          headers: { "If-Match": state.revision },
          body: { definition: state.draft },
        },
      );
    } catch (error) {
      if (error.status === 409 || error.status === 412) {
        showValidation(
          "error",
          "저장 충돌: 파일이 외부에서 변경되었습니다. 현재 draft를 복사한 뒤 콘텐츠를 새로고침해 병합하세요.",
        );
        toast("외부 변경 때문에 저장하지 않았습니다.", "error");
      } else {
        showValidation("error", `저장 실패\n${errorMessage(error)}`);
        toast("저장에 실패했습니다. 저장 상태를 확인하세요.", "error");
      }
      return;
    }

    const warnings = Array.isArray(result?.warnings)
      ? result.warnings.map((warning) => String(warning)).filter(Boolean)
      : [];
    try {
      applySavedContent(result);
    } catch (error) {
      warnings.push(`메이커 화면 반영 실패: ${errorMessage(error)}`);
    }
    try {
      await refreshGraph(false, { notify: false });
    } catch (error) {
      warnings.push(`참조 그래프 동기화 실패: ${errorMessage(error)}`);
    }

    if (warnings.length > 0) {
      showValidation(
        "neutral",
        `저장 및 런타임 reload 성공 · revision ${shortRevision(state.revision)}\n주의: ${warnings.join("\n")}`,
      );
      toast(`저장은 반영되었습니다. 주의: ${warnings.join(" / ")}`);
    } else {
      showValidation(
        "success",
        `저장 및 런타임 reload 성공 · revision ${shortRevision(state.revision)}`,
      );
      toast("콘텐츠를 저장하고 게임에 반영했습니다.", "success");
    }
    requestScreenshotSoon(80);
  } finally {
    button.disabled = Boolean(state.current?.read_only);
    button.textContent = originalText;
  }
}

const createReferenceRules = {
  projectile: {
    kind: "actor",
    required: false,
    label: "Projectile Actor",
    help: "비우면 projectile 표시용 actor도 함께 생성합니다.",
  },
  encounter: {
    kind: "actor",
    required: true,
    label: "첫 적 Actor",
    help: "첫 wave에 배치할 actor를 선택합니다.",
  },
  shop: {
    kind: "item",
    required: true,
    label: "첫 판매 Item",
    help: "첫 offer에 등록할 item을 선택합니다.",
  },
  "turn-battle": {
    kind: "actor",
    required: true,
    label: "첫 적 Battler Actor",
    help: "rpg.turn_battler 컴포넌트가 있는 actor를 선택합니다.",
  },
};

function updateCreateReference() {
  const kind = $("#create-kind").value;
  const rule = createReferenceRules[kind];
  const row = $("#create-reference-row");
  const select = $("#create-reference");
  row.hidden = !rule;
  select.required = Boolean(rule?.required);
  select.replaceChildren();
  if (!rule) {
    return;
  }
  $("#create-reference-label").textContent = rule.label;
  $("#create-reference-help").textContent = rule.help;
  const blank = createElement(
    "option",
    "",
    rule.required ? "선택하세요" : "자동 생성",
  );
  blank.value = "";
  select.append(blank);
  for (const node of sortedNodes().filter((item) => item.kind === rule.kind)) {
    const option = createElement("option", "", node.id);
    option.value = node.id;
    select.append(option);
  }
}

function openCreateDialog() {
  if (!confirmDiscard()) {
    return;
  }
  updateCreateReference();
  $("#create-dialog").showModal();
  window.setTimeout(() => $("#create-name").focus(), 0);
}

function closeCreateDialog() {
  $("#create-dialog").close();
  $("#create-form").reset();
  updateCreateReference();
}

function createdContentID(kind, name) {
  const contentKind = {
    equipment: "item",
    "turn-skill": "turn_skill",
    "turn-battle": "turn_battle",
  }[kind] || kind;
  return `${contentKind}.${name}`;
}

async function createContent(event) {
  event.preventDefault();
  const form = $("#create-form");
  if (!form.reportValidity()) {
    return;
  }
  const kind = $("#create-kind").value;
  const name = $("#create-name").value.trim();
  const reference = $("#create-reference-row").hidden
    ? ""
    : $("#create-reference").value;
  const button = $("#submit-create");
  button.disabled = true;
  button.textContent = "만드는 중…";
  try {
    const result = await apiJSON("/api/content/create", {
      method: "POST",
      body: { kind, name, reference },
    });
    const warnings = Array.isArray(result?.warnings)
      ? result.warnings.map((warning) => String(warning)).filter(Boolean)
      : [];
    if (result.graph_synced !== false && result.graph) {
      setGraph(result.graph);
    } else {
      try {
        await refreshGraph(true, { notify: false });
      } catch (error) {
        warnings.push(`참조 그래프 동기화 실패: ${errorMessage(error)}`);
      }
    }
    closeCreateDialog();
    if (warnings.length > 0) {
      toast(
        `${createdContentID(kind, name)} 콘텐츠는 만들었습니다. 주의: ${warnings.join(" / ")}`,
      );
    } else {
      toast(`${createdContentID(kind, name)} 콘텐츠를 만들었습니다.`, "success");
    }
    await selectContent(createdContentID(kind, name), {
      skipDirtyCheck: true,
      force: true,
    });
    requestScreenshotSoon(100);
  } catch (error) {
    toast(errorMessage(error), "error");
  } finally {
    button.disabled = false;
    button.textContent = "만들기";
  }
}

const previewKinds = new Set(["stage", "actor", "dialogue", "ability"]);

function populatePreviewIDs(preferredID = "") {
  const type = $("#preview-type").value;
  const select = $("#preview-id");
  const previous = preferredID || select.value;
  const nodes = sortedNodes().filter((node) => node.kind === type);
  select.replaceChildren();
  for (const node of nodes) {
    const option = createElement("option", "", node.id);
    option.value = node.id;
    select.append(option);
  }
  if (nodes.some((node) => node.id === previous)) {
    select.value = previous;
  }
  updatePreviewFields();
}

function updatePreviewFields() {
  const type = $("#preview-type").value;
  $("#stage-preview-fields").hidden = type !== "stage";
  $("#actor-preview-fields").hidden = type !== "actor";
  $("#dialogue-preview-fields").hidden = type !== "dialogue";
  $("#ability-preview-fields").hidden = type !== "ability";
}

function syncPreviewToSelection() {
  const kind = state.current?.kind;
  if (!previewKinds.has(kind)) {
    return;
  }
  $("#preview-type").value = kind;
  populatePreviewIDs(state.current.id);
}

function previewPayload() {
  const type = $("#preview-type").value;
  const payload = {
    type,
    id: $("#preview-id").value,
  };
  if (type === "stage") {
    const spawn = $("#preview-spawn").value.trim();
    if (spawn) {
      payload.spawn = spawn;
    }
  } else if (type === "actor") {
    payload.position = $("#preview-position").checked;
    if (payload.position) {
      payload.x = Number($("#preview-x").value);
      payload.y = Number($("#preview-y").value);
    }
  } else if (type === "dialogue") {
    const speaker = $("#preview-speaker").value.trim();
    if (speaker) {
      payload.speaker_id = speaker;
    }
  } else if (type === "ability") {
    const entity = $("#preview-entity").value.trim();
    if (entity) {
      payload.entity_id = entity;
    }
  }
  return payload;
}

async function runPreview(event) {
  event?.preventDefault();
  const payload = previewPayload();
  if (!payload.id) {
    toast("미리 볼 콘텐츠 ID가 없습니다.", "error");
    return;
  }
  const resultElement = $("#preview-result");
  resultElement.className = "preview-result";
  resultElement.textContent = `${payload.type} 미리보기를 실행하는 중…`;
  try {
    const result = await apiJSON("/api/preview", {
      method: "POST",
      body: payload,
    });
    resultElement.textContent = JSON.stringify(result, null, 2);
    await refreshProject();
    requestScreenshotSoon(80);
    toast(`${payload.id} 미리보기를 실행했습니다.`, "success");
  } catch (error) {
    resultElement.classList.add("error");
    resultElement.textContent = errorMessage(error);
    toast(errorMessage(error), "error");
  }
}

function previewSelected() {
  if (!state.current || !previewKinds.has(state.current.kind)) {
    toast("이 콘텐츠 종류는 직접 미리보기를 지원하지 않습니다.", "error");
    return;
  }
  syncPreviewToSelection();
  runPreview();
}

async function fetchScreenshot() {
  return enqueueRequest(async () => {
    let response;
    try {
      response = await fetch(`/api/screenshot?t=${Date.now()}`, {
        cache: "no-store",
        headers: {
          Accept: "image/png",
          "X-Recreate-Token": token,
        },
      });
    } catch (error) {
      throw new APIError(`화면 요청 실패: ${error.message}`);
    }
    if (!response.ok) {
      let message = `화면 요청 실패 (HTTP ${response.status})`;
      try {
        const payload = await response.json();
        message = payload.error || message;
      } catch {
        // Keep the HTTP fallback message.
      }
      throw new APIError(message, response.status);
    }
    return response.blob();
  });
}

async function refreshScreenshot({ manual = false } = {}) {
  if (state.screenshotBusy) {
    return;
  }
  state.screenshotBusy = true;
  const status = $("#screen-status");
  status.textContent = "캡처 중";
  status.className = "screen-status";
  try {
    const blob = await fetchScreenshot();
    const url = URL.createObjectURL(blob);
    const previous = state.screenshotURL;
    state.screenshotURL = url;
    const image = $("#game-screen");
    image.addEventListener(
      "load",
      () => {
        if (previous) {
          URL.revokeObjectURL(previous);
        }
      },
      { once: true },
    );
    image.src = url;
    $("#screen-placeholder").hidden = true;
    status.textContent = state.screenshotLive ? "LIVE" : "갱신됨";
    status.className =
      `screen-status${state.screenshotLive ? " live" : ""}`;
  } catch (error) {
    status.textContent = "오류";
    status.className = "screen-status error";
    if (manual) {
      toast(errorMessage(error), "error");
    }
  } finally {
    state.screenshotBusy = false;
    scheduleScreenshot();
  }
}

function scheduleScreenshot(delay) {
  window.clearTimeout(state.screenshotTimer);
  if (!state.screenshotLive) {
    return;
  }
  const interval =
    delay ?? (document.visibilityState === "visible" ? 850 : 2800);
  state.screenshotTimer = window.setTimeout(
    () => refreshScreenshot(),
    interval,
  );
}

function requestScreenshotSoon(delay = 50) {
  if (state.screenshotLive) {
    scheduleScreenshot(delay);
  } else {
    refreshScreenshot();
  }
}

function setScreenshotLive(enabled) {
  state.screenshotLive = enabled;
  if (enabled) {
    $("#screen-status").textContent = "연결 중";
    scheduleScreenshot(0);
  } else {
    window.clearTimeout(state.screenshotTimer);
    $("#screen-status").textContent = "일시정지";
    $("#screen-status").className = "screen-status";
  }
}

function inputFrames() {
  const parsed = Number.parseInt($("#input-frames").value, 10);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 600) {
    return 1;
  }
  return parsed;
}

function pulseInputButton(action) {
  const button = $(`[data-input-action="${CSS.escape(action)}"]`);
  if (!button) {
    return;
  }
  button.classList.add("pressed");
  window.setTimeout(() => button.classList.remove("pressed"), 180);
}

async function sendSemanticInput(action) {
  if (!action) {
    return;
  }
  pulseInputButton(action);
  const resultElement = $("#preview-result");
  resultElement.className = "preview-result";
  resultElement.textContent = `${action} 입력 전송 중…`;
  try {
    const result = await apiJSON("/api/input", {
      method: "POST",
      body: { action, frames: inputFrames() },
    });
    resultElement.textContent = JSON.stringify(result, null, 2);
    requestScreenshotSoon(40);
  } catch (error) {
    resultElement.classList.add("error");
    resultElement.textContent = errorMessage(error);
    toast(errorMessage(error), "error");
  }
}

function editableTarget(target) {
  return Boolean(
    target.closest(
      "input, textarea, select, [contenteditable='true'], dialog",
    ),
  );
}

const keyboardActions = {
  w: "move_up",
  arrowup: "move_up",
  s: "move_down",
  arrowdown: "move_down",
  a: "move_left",
  arrowleft: "move_left",
  d: "move_right",
  arrowright: "move_right",
  " ": "attack",
  e: "interact",
  c: "parry",
  shift: "dodge",
  f: "special",
  q: "technique",
  enter: "menu_confirm",
  escape: "menu_cancel",
};

function handleRuntimeKeyboard(event) {
  if (event.ctrlKey || event.metaKey || event.altKey || editableTarget(event.target)) {
    return;
  }
  if (event.repeat) {
    return;
  }
  const action = keyboardActions[event.key.toLocaleLowerCase()];
  if (!action) {
    return;
  }
  event.preventDefault();
  sendSemanticInput(action);
}

function bindEditorEvents() {
  const form = $("#structured-form");
  form.addEventListener("input", (event) => {
    const input = event.target.closest('[data-editor-role="primitive"]');
    if (input) {
      updatePrimitiveFromInput(input);
    }
  });
  form.addEventListener("change", (event) => {
    const target = event.target;
    if (target.matches('[data-editor-role="type"]')) {
      changeValueType(target);
    } else if (
      target.matches('[data-editor-role="primitive"][data-value-type="boolean"]')
    ) {
      updatePrimitiveFromInput(target);
    }
  });
  form.addEventListener("click", (event) => {
    const button = event.target.closest("[data-editor-action]");
    if (!button) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const action = button.dataset.editorAction;
    const path = readPath(button);
    if (action === "delete") {
      deleteAtPath(path);
    } else if (action === "rename") {
      renameAtPath(path);
    } else if (action === "add") {
      addAtPath(button);
    } else if (action === "add-action") {
      addActionAtPath(button);
    } else if (action === "create-action-list") {
      createActionListAtPath(path);
    } else if (action === "add-condition") {
      addConditionAtPath(path);
    } else if (action === "add-dialogue-node") {
      addDialogueNode(path);
    } else if (action === "add-dialogue-choice") {
      addDialogueChoice(path);
    } else if (action === "add-quest-objective") {
      addQuestObjective(path);
    } else if (action === "add-turn-battle-enemy") {
      addTurnBattleEnemy(path);
    } else if (action === "add-cutscene-step") {
      addCutsceneStep(path);
    } else if (action === "add-battler-skill") {
      addBattlerSkill(path);
    } else if (action === "add-event-page") {
      addEventPage(path, button.dataset.eventPageKind || "interaction");
    } else if (action === "add-world-page") {
      addWorldPage(path);
    } else if (action === "add-world-layer") {
      addWorldLayer(path);
    } else if (action === "ensure-interactable") {
      ensureInteractable(path);
    } else if (action === "save-map-object") {
      saveMapObject(Number(path[path.length - 1]), button);
    } else if (action === "save-map-world-pages") {
      saveMapWorldPages(button);
    } else if (action === "load-more") {
      loadMore(path);
    }
  });
  form.addEventListener("keydown", (event) => {
    if (
      event.key === "Enter" &&
      event.target.matches('[data-editor-role="new-key"]')
    ) {
      event.preventDefault();
      const button = $('[data-editor-action="add"]', event.target.closest(".add-row"));
      button?.click();
    }
  });
}

function bindUIEvents() {
  $("#refresh-project").addEventListener("click", () => {
    refreshProject().catch(() => {});
  });
  $("#refresh-graph").addEventListener("click", () => {
    refreshGraph(true).catch(() => {});
  });
  $("#content-search").addEventListener("input", (event) => {
    state.search = event.target.value;
    renderContentList();
  });
  $("#kind-list").addEventListener("click", (event) => {
    const button = event.target.closest("[data-kind]");
    if (!button) {
      return;
    }
    state.selectedKind = button.dataset.kind;
    renderKinds();
    renderContentList();
  });
  $("#content-list").addEventListener("click", (event) => {
    const item = event.target.closest("[data-content-id]");
    if (item) {
      selectContent(item.dataset.contentId);
    }
  });
  for (const container of [$("#dependency-list"), $("#dependent-list")]) {
    container.addEventListener("click", (event) => {
      const item = event.target.closest("[data-content-id]");
      if (item) {
        selectContent(item.dataset.contentId);
      }
    });
  }

  $$(".editor-tab").forEach((button) => {
    button.addEventListener("click", () => switchTab(button.dataset.tab));
  });
  $("#validate-content").addEventListener("click", validateCurrent);
  $("#save-content").addEventListener("click", saveCurrent);
  $("#preview-selected").addEventListener("click", previewSelected);

  $("#json-editor").addEventListener("input", () => {
    state.jsonDirty = true;
    setDirty(true);
    setJSONStatus("입력 중…", "");
    window.clearTimeout(state.jsonParseTimer);
    state.jsonParseTimer = window.setTimeout(
      () => parseJSONEditor({ quiet: true }),
      350,
    );
  });
  $("#json-editor").addEventListener("keydown", (event) => {
    if (event.key !== "Tab") {
      return;
    }
    event.preventDefault();
    const textarea = event.target;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    textarea.setRangeText("  ", start, end, "end");
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  });

  $("#open-create").addEventListener("click", openCreateDialog);
  $("#close-create").addEventListener("click", closeCreateDialog);
  $("#cancel-create").addEventListener("click", closeCreateDialog);
  $("#create-kind").addEventListener("change", updateCreateReference);
  $("#create-form").addEventListener("submit", createContent);
  $("#create-dialog").addEventListener("click", (event) => {
    if (event.target === $("#create-dialog")) {
      closeCreateDialog();
    }
  });

  $("#preview-type").addEventListener("change", () => populatePreviewIDs());
  $("#preview-form").addEventListener("submit", runPreview);
  $("#refresh-screen").addEventListener("click", () => {
    refreshScreenshot({ manual: true });
  });
  $("#live-screenshot").addEventListener("change", (event) => {
    setScreenshotLive(event.target.checked);
  });
  $("#action-pad").addEventListener("click", (event) => {
    const button = event.target.closest("[data-input-action]");
    if (button) {
      sendSemanticInput(button.dataset.inputAction);
    }
  });
  $(".movement-pad").addEventListener("click", (event) => {
    const button = event.target.closest("[data-input-action]");
    if (button) {
      sendSemanticInput(button.dataset.inputAction);
    }
  });
  $(".menu-inputs").addEventListener("click", (event) => {
    const button = event.target.closest("[data-input-action]");
    if (button) {
      sendSemanticInput(button.dataset.inputAction);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (
      (event.ctrlKey || event.metaKey) &&
      event.key.toLocaleLowerCase() === "s"
    ) {
      if (state.current) {
        event.preventDefault();
        saveCurrent();
      }
      return;
    }
    if (
      event.key === "/" &&
      !event.ctrlKey &&
      !event.metaKey &&
      !editableTarget(event.target)
    ) {
      event.preventDefault();
      $("#content-search").focus();
      return;
    }
    handleRuntimeKeyboard(event);
  });
  document.addEventListener("visibilitychange", () => {
    if (state.screenshotLive) {
      scheduleScreenshot(100);
    }
  });
  window.addEventListener("beforeunload", (event) => {
    if (!state.dirty) {
      return;
    }
    event.preventDefault();
    event.returnValue = "";
  });
}

async function initialize() {
  bindEditorEvents();
  bindUIEvents();
  updateCreateReference();
  populatePreviewIDs();
  try {
    await refreshProject({ initial: true });
  } catch {
    // The status and toast already explain the connection failure.
  }
  setScreenshotLive(true);
}

initialize();
