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
      const initialNode =
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
  setDirty(stableText(state.draft) !== stableText(state.originalDefinition));
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
    content.read_only
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
  let value = state.draft;
  for (const segment of path) {
    if (value === null || value === undefined) {
      return undefined;
    }
    value = value[segment];
  }
  return value;
}

function setAtPath(path, value) {
  if (path.length === 0) {
    state.draft = value;
    return;
  }
  const parent = getAtPath(path.slice(0, -1));
  if (parent !== null && parent !== undefined) {
    parent[path[path.length - 1]] = value;
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

function primitiveEditor(value, path, locked) {
  const kind = valueKind(value);
  const wrapper = createElement("div", "field-value");
  let input;

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
  const details = createElement(
    "details",
    `structure-node${root ? " root-node" : ""}`,
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
      kind === "array"
        ? `${value.length}개 항목`
        : `${Object.keys(value).length}개 필드`,
    ),
  );
  if (!root) {
    summary.append(typeSelect(value, path, locked), deleteButton(path, locked));
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

function renderStructuredForm() {
  const container = $("#structured-form");
  container.replaceChildren();
  if (!state.draft) {
    return;
  }
  container.append(
    renderValue(state.draft, [], "definition", "object", 0, true),
  );
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
  return `${kind === "equipment" ? "item" : kind}.${name}`;
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
