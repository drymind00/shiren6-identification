const CSV_URL = '../../outputs/shiren6_notion_import/シレン6 アイテム図鑑・値段識別_インポート用.csv';
const baseColumns = ['アイテム名', '識別済', 'カテゴリ', '買値', '売値', '容量・回数', '識別方法', 'メモ'];
const secondaryCategories = ['武器', '盾', '矢・石', '食料'];
const equipmentCategories = new Set(['武器', '盾']);
const minEnhancement = -1;
const maxEnhancement = 3;
const variableCapacityRanges = new Map([
  ['ビックリの壺', { min: 3, max: 5 }],
  ['背中の壺', { min: 3, max: 5 }],
]);
const state = { items: [], dungeons: [], categories: [], selected: new Set(), dungeon: '', categories: new Set(), price: '', priceType: 'buy', condition: 'normal' };

const $ = (selector) => document.querySelector(selector);
const escapeHtml = (value) => String(value || '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]);

function parseCsv(text) {
  const rows = []; let row = []; let value = ''; let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i]; const next = text[i + 1];
    if (char === '"' && quoted && next === '"') { value += char; i += 1; }
    else if (char === '"') quoted = !quoted;
    else if (char === ',' && !quoted) { row.push(value); value = ''; }
    else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') i += 1;
      row.push(value); if (row.some((cell) => cell)) rows.push(row); row = []; value = '';
    } else value += char;
  }
  if (value || row.length) { row.push(value); rows.push(row); }
  const [headers, ...records] = rows;
  return records.map((record) => Object.fromEntries(headers.map((header, index) => [header, record[index] || ''])));
}

function adjustedPrice(item, type) {
  const normalPrice = Number(item[type === 'buy' ? '買値' : '売値']);
  if (!Number.isFinite(normalPrice)) return null;
  if (state.condition === 'blessed') return normalPrice * 2;
  if (state.condition === 'cursed') return Math.floor(normalPrice * 0.87);
  return normalPrice;
}

function capacityPriceOptions(item, type) {
  const priceIndex = type === 'buy' ? 2 : 3;
  const options = [];
  const pattern = /\[([^\]]+)\]\s*(\d+)\s*\/\s*(\d+)/g;
  for (const match of item['容量・回数'].matchAll(pattern)) {
    options.push({ price: Number(match[priceIndex]), capacity: match[1] });
  }
  const variableCapacityPattern = /容量1ごとに買値\+(\d+)・売値\+(\d+)/;
  const variableCapacity = item['容量・回数'].match(variableCapacityPattern);
  if (variableCapacity) {
    const variablePriceIndex = type === 'buy' ? 1 : 2;
    const capacityRange = variableCapacityRanges.get(item['アイテム名']);
    if (capacityRange) {
      options.push({
        price: Number(item[type === 'buy' ? '買値' : '売値']),
        capacityStep: Number(variableCapacity[variablePriceIndex]),
        capacityRange,
      });
    }
  }
  return options;
}

function adjustedPriceValue(price) {
  if (state.condition === 'blessed') return price * 2;
  if (state.condition === 'cursed') return Math.floor(price * 0.87);
  return price;
}

function variableCapacityMatches(option, observedPrice) {
  const { price, capacityStep, capacityRange } = option;
  const possibleCapacities = Array.from(
    { length: capacityRange.max - capacityRange.min + 1 },
    (_, index) => capacityRange.min + index,
  );
  const priceForCapacity = (capacity) => price + ((capacity - capacityRange.min) * capacityStep);
  if (state.condition === 'normal') {
    return possibleCapacities.filter((capacity) => priceForCapacity(capacity) === observedPrice);
  }
  if (state.condition === 'blessed') {
    return possibleCapacities.filter((capacity) => priceForCapacity(capacity) * 2 === observedPrice);
  }
  return possibleCapacities.filter((capacity) => adjustedPriceValue(priceForCapacity(capacity)) === observedPrice);
}

function matchingPriceDetails(item, type, observedPrice) {
  const normalPrice = Number(item[type === 'buy' ? '買値' : '売値']);
  if (!Number.isFinite(normalPrice)) return [];

  const priceOptions = capacityPriceOptions(item, type);
  if (!priceOptions.length) priceOptions.push({ price: normalPrice, capacity: null });

  const enhancementStep = type === 'buy' ? 100 : 40;
  const enhancements = equipmentCategories.has(item['カテゴリ'])
    ? Array.from({ length: maxEnhancement - minEnhancement + 1 }, (_, index) => minEnhancement + index)
    : [0];

  return priceOptions.flatMap((option) => {
    if (option.capacityStep) {
      return variableCapacityMatches(option, observedPrice).map((capacity) => ({ capacity, variableCapacity: true, enhancement: 0 }));
    }
    return enhancements.flatMap((enhancement) => {
      const enhancedPrice = option.price + (enhancement * enhancementStep);
      const adjusted = adjustedPriceValue(enhancedPrice);
      if (adjusted !== observedPrice) return [];
      return [{ capacity: option.capacity, enhancement }];
    });
  });
}

function matchesObservedPrice(item, type, observedPrice) {
  return matchingPriceDetails(item, type, observedPrice).length > 0;
}

function enhancementLabel(enhancement) {
  if (enhancement === 0) return '強化値±0';
  return `強化値${enhancement > 0 ? '+' : ''}${enhancement}`;
}

function priceMatchText(item) {
  if (state.price === '') return '';
  const observedPrice = Number(state.price);
  const matches = matchingPriceDetails(item, state.priceType, observedPrice);
  if (!matches.length) return '';
  const details = matches.map(({ capacity, variableCapacity, enhancement }) => {
    const labels = [];
    if (capacity !== null && capacity !== undefined) {
      if (variableCapacity) labels.push(`容量${capacity}`);
      else labels.push(`${item['カテゴリ'] === '壺' ? '容量' : '回数'}${capacity}`);
    }
    if (equipmentCategories.has(item['カテゴリ'])) labels.push(enhancementLabel(enhancement));
    return labels.join('・') || '通常価格';
  }).join(' / ');
  return `価格一致: ${priceLabel(state.priceType)} ${observedPrice}（${details}）`;
}

function priceLabel(type) {
  const labels = { normal: '', blessed: '（祝福）', cursed: '（呪い）' };
  return `${type === 'buy' ? '買値' : '売値'}${labels[state.condition]}`;
}

function filteredItems() {
  const observedPrice = state.price === '' ? null : Number(state.price);
  return state.items.filter((item) =>
    (!state.dungeon || item[state.dungeon] === 'Yes') &&
    (!state.categories.size || state.categories.has(item['カテゴリ'])) &&
    (observedPrice === null || matchesObservedPrice(item, state.priceType, observedPrice))
  );
}

function render() {
  const items = filteredItems().sort((left, right) =>
    Number(state.selected.has(left['アイテム名'])) - Number(state.selected.has(right['アイテム名']))
  );
  $('#result-count').textContent = `${items.length}件の候補（チェック済み ${state.selected.size}件）`;
  const template = $('#item-template'); const list = $('#item-list'); list.replaceChildren();
  for (const item of items) {
    const fragment = template.content.cloneNode(true); const card = fragment.querySelector('.item-card');
    const check = fragment.querySelector('.item-check'); check.checked = state.selected.has(item['アイテム名']); check.dataset.name = item['アイテム名'];
    fragment.querySelector('.item-name').textContent = item['アイテム名'];
    fragment.querySelector('.buy-label').textContent = priceLabel('buy');
    fragment.querySelector('.sell-label').textContent = priceLabel('sell');
    fragment.querySelector('.buy-price').textContent = adjustedPrice(item, 'buy') ?? '—';
    fragment.querySelector('.sell-price').textContent = adjustedPrice(item, 'sell') ?? '—';
    fragment.querySelector('.capacity').textContent = item['容量・回数'] || '—';
    const priceMatch = priceMatchText(item);
    const priceMatchElement = fragment.querySelector('.price-match');
    priceMatchElement.textContent = priceMatch;
    priceMatchElement.hidden = !priceMatch;
    fragment.querySelector('.memo').textContent = item['メモ'] || item['識別方法'] || '';
    list.append(card);
  }
  if (!items.length) list.innerHTML = '<p>条件に一致するアイテムがありません。</p>';
}

function resetSelection(message) {
  state.selected.clear(); render();
  const notice = $('#notice'); notice.textContent = message; notice.hidden = false;
}

function setupFilters() {
  $('#dungeon-select').innerHTML = `<option value="">すべてのダンジョン</option>${state.dungeons.map((name) => `<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`).join('')}`;
  const categoryChip = (name) => `<label><input type="checkbox" value="${escapeHtml(name)}">${escapeHtml(name)}</label>`;
  const mainCategories = state.categories.filter((name) => !secondaryCategories.includes(name));
  const bottomCategories = secondaryCategories.filter((name) => state.categories.includes(name));
  $('#category-options').innerHTML = `<div class="category-main-row">${mainCategories.map(categoryChip).join('')}</div><div class="category-secondary-row">${bottomCategories.map(categoryChip).join('')}</div>`;
  $('#dungeon-select').addEventListener('change', (event) => { state.dungeon = event.target.value; render(); });
  $('#category-options').addEventListener('change', () => { state.categories = new Set([...document.querySelectorAll('#category-options input:checked')].map((input) => input.value)); render(); });
  $('#price-search').addEventListener('input', (event) => { state.price = event.target.value; render(); });
  $('#price-type').addEventListener('change', (event) => { state.priceType = event.target.value; render(); });
  document.querySelectorAll('input[name="condition"]').forEach((input) => input.addEventListener('change', (event) => { state.condition = event.target.value; render(); }));
  $('#item-list').addEventListener('change', (event) => { if (!event.target.matches('.item-check')) return; event.target.checked ? state.selected.add(event.target.dataset.name) : state.selected.delete(event.target.dataset.name); render(); });
  $('#clear-current').addEventListener('click', () => {
    if (!state.selected.size || window.confirm('選択中のチェックをすべて解除しますか？')) {
      resetSelection('選択中のチェックを解除しました。');
    }
  });
}

fetch(CSV_URL).then((response) => { if (!response.ok) throw new Error(response.status); return response.text(); }).then((text) => {
  state.items = parseCsv(text);
  const headers = Object.keys(state.items[0] || {});
  state.dungeons = headers.filter((header) => !baseColumns.includes(header));
  state.categories = [...new Set(state.items.map((item) => item['カテゴリ']).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'ja'));
  setupFilters(); render();
}).catch(() => {
  $('#result-count').textContent = 'データを読み込めませんでした。';
  const notice = $('#notice'); notice.hidden = false;
  notice.textContent = 'このツールはローカルサーバーで開いてください。リポジトリのルートで tools\\start_shiren6_identification_tool.ps1 を実行します。';
});
