// Cloudflare Worker for Muse. Keeps the Gemini key secret.
//   { image }                  -> { name, category, color }                 tag one item
//   { image, mode: "detect" }  -> { items: [{ name, category, color, box }] }  find items in a wardrobe photo
//   { mode: "style", looks, note, items }        -> { ids, reason }          pick an outfit from the closet
//   { mode: "match", looks, note, worn, items }  -> { closet_ids, to_buy }   what goes with what is worn
// "style" and "match" send text only (no photos).

const MODEL = "gemini-2.5-flash"; // change if Google retires this model
const CATEGORIES = ["Tops", "Bottoms", "Dresses", "Jackets", "Shoes", "Accessories"];
const CAT_LIST = "one of: Tops, Bottoms, Dresses, Jackets, Shoes, Accessories";

const TAG_PROMPT =
  "This is a photo of one clothing item or accessory. Reply with JSON only: " +
  `{"name": "short name, 2-4 words", "category": "${CAT_LIST}", "color": "main color, 1-2 words"}`;

const DETECT_PROMPT =
  "This is a photo of clothes (a wardrobe, closet, rack, bed or pile). Find each separate clothing " +
  "item, shoe or accessory that is clearly visible, at most 12. Reply with JSON only: a list of " +
  `{"name": "short name, 2-4 words", "category": "${CAT_LIST}", "color": "main color, 1-2 words", ` +
  '"box_2d": [ymin, xmin, ymax, xmax]} with box_2d normalized to 0-1000.';

const STYLE_RULES =
  "You are a friendly personal stylist. Talk only about style: color, cut, fabric, occasion. " +
  "Never comment on attractiveness or judge anyone's body. ";

const stylePrompt = (looks, note, items) =>
  STYLE_RULES +
  `The user describes themselves: ${looks}. Occasion or notes: ${note || "none"}. ` +
  "Pick ONE outfit using only items from this closet, referring to each item by its exact id: " +
  `${JSON.stringify(items)}. Use at most one item per category, either a Dress or a Top plus Bottoms, ` +
  "and add Shoes, a Jacket or an Accessory only if they suit. Prefer colors that flatter the skin tone. " +
  'Reply with JSON only: {"ids": ["..."], "reason": "1-2 friendly sentences"}.';

const matchPrompt = (looks, note, worn, items) =>
  STYLE_RULES +
  `The user describes themselves: ${looks}. They are wearing: ${JSON.stringify(worn)}. ` +
  `What they are looking for: ${note || "anything that completes the outfit"}. ` +
  `Their closet (other items): ${JSON.stringify(items)}. ` +
  "Suggest pieces that go well with what they are wearing, including shoes, jewelry or other accessories. " +
  'Reply with JSON only: {"closet_ids": ["ids from the closet that go well, max 4"], ' +
  '"to_buy": [{"item": "e.g. white leather sneakers", "category": "category", "why": "short reason", ' +
  '"search": "words to search for it in an online shop"}]} with at most 4 to_buy entries.';

async function askGemini(env, prompt, image) {
  const parts = [{ text: prompt }];
  if (image) parts.push({ inline_data: { mime_type: "image/jpeg", data: image } });
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { responseMimeType: "application/json" },
      }),
    }
  );
  if (!res.ok) throw new Error("AI request failed " + res.status);
  const data = await res.json();
  return JSON.parse(data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "");
}

const norm = (n) => Math.min(1, Math.max(0, Number(n) / 1000));
const cat = (c) => (CATEGORIES.includes(c) ? c : null);
const clean = (v, n) => String(v ?? "").replace(/[\r\n]+/g, " ").slice(0, n);
const cleanItems = (arr, max = 60) =>
  (Array.isArray(arr) ? arr : []).slice(0, max).map((i) => ({
    id: clean(i.id, 40),
    name: clean(i.name, 40),
    category: clean(i.category, 20),
    color: clean(i.color, 30),
  }));

export default {
  async fetch(request, env) {
    const headers = {
      "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Content-Type": "application/json",
    };
    const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers });

    if (request.method === "OPTIONS") return new Response(null, { headers });
    if (request.method !== "POST") return reply({ error: "Use POST" }, 405);

    let body;
    try {
      body = await request.json();
    } catch {
      return reply({ error: "Bad JSON" }, 400);
    }

    try {
      if (body.mode === "style" || body.mode === "match") {
        const looks = clean(body.looks, 200);
        const note = clean(body.note, 120);
        const items = cleanItems(body.items);
        const valid = new Set(items.map((i) => i.id));
        if (body.mode === "style") {
          if (!items.length) return reply({ error: "Empty closet" }, 400);
          const out = await askGemini(env, stylePrompt(looks, note, items));
          const ids = (Array.isArray(out.ids) ? out.ids : []).map(String).filter((id) => valid.has(id));
          return reply({ ids: ids.slice(0, 6), reason: clean(out.reason, 300) });
        }
        const worn = cleanItems(body.worn, 6);
        if (!worn.length) return reply({ error: "Nothing worn" }, 400);
        const out = await askGemini(env, matchPrompt(looks, note, worn, items));
        const closetIds = (Array.isArray(out.closet_ids) ? out.closet_ids : [])
          .map(String)
          .filter((id) => valid.has(id));
        const toBuy = (Array.isArray(out.to_buy) ? out.to_buy : [])
          .slice(0, 4)
          .map((t) => ({
            item: clean(t.item, 60),
            category: clean(t.category, 20),
            why: clean(t.why, 120),
            search: clean(t.search, 80),
          }))
          .filter((t) => t.item && t.search);
        return reply({ closet_ids: closetIds.slice(0, 4), to_buy: toBuy });
      }

      const image = body.image;
      if (typeof image !== "string" || !image || image.length > 4_000_000) {
        return reply({ error: "Missing or too large image" }, 400);
      }

      if (body.mode === "detect") {
        const out = await askGemini(env, DETECT_PROMPT, image);
        const list = Array.isArray(out) ? out : out.items ?? [];
        const items = list
          .slice(0, 12)
          .map((e) => {
            const b = e.box_2d;
            if (!Array.isArray(b) || b.length !== 4) return null;
            const [ymin, xmin, ymax, xmax] = b.map(norm);
            if (xmax - xmin < 0.03 || ymax - ymin < 0.03) return null;
            return {
              name: clean(e.name ?? "Item", 40),
              category: cat(e.category),
              color: clean(e.color, 30),
              box: [xmin, ymin, xmax, ymax],
            };
          })
          .filter(Boolean);
        return reply({ items });
      }

      const out = await askGemini(env, TAG_PROMPT, image);
      return reply({ name: clean(out.name, 40), category: cat(out.category), color: clean(out.color, 30) });
    } catch {
      return reply({ error: "AI request failed" }, 502);
    }
  },
};
