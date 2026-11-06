// Cloudflare Worker for Muse. Keeps the Gemini key secret.
//   { image }                  -> { name, category, color }                 tag one item
//   { image, mode: "detect" }  -> { items: [{ name, category, color, box }] }  find items in a wardrobe photo
//   { mode: "style", looks, note, items }        -> { ids, reason }          pick an outfit from the closet
//   { mode: "match", looks, note, worn, items }  -> { closet_ids, to_buy }   what goes with what is worn
//   { image, mode: "flatten", category, bg }  -> { image, mime }  front-facing photo that fits the model (paid key)
// "style" and "match" send text only (no photos).

const MODEL = "gemini-flash-lite-latest"; // Google keeps this pointing at the newest Flash-Lite model (fast, free-tier friendly)
const CATEGORIES = ["Tops", "Bottoms", "Dresses", "Jackets", "Shoes", "Accessories"];
const CAT_LIST = "one of: Tops, Bottoms, Dresses, Jackets, Shoes, Accessories";

// What the app needs to draw a clean flat picture of the piece.
const LOOK_FIELDS =
  '"hex": "#RRGGBB main color of the item", "hex2": "#RRGGBB second color (stripes, trim, print) or the same as hex", ' +
  '"pattern": "one of: solid, stripes, checks, dots", "sleeves": "one of: none, short, long", ' +
  '"length": "one of: short, regular, long", "neckline": "one of: round, v, collar", ' +
  '"bottom_type": "one of: pants, shorts, skirt"';

const TAG_PROMPT =
  "This is a photo of one clothing item or accessory. Reply with JSON only: " +
  `{"name": "short name, 2-4 words", "category": "${CAT_LIST}", "color": "main color, 1-2 words", ${LOOK_FIELDS}}`;

const DETECT_PROMPT =
  "This is a photo of clothes (a wardrobe, closet, rack, bed or pile). Find each separate clothing " +
  "item, shoe or accessory that is clearly visible, at most 12. Reply with JSON only: a list of " +
  `{"name": "short name, 2-4 words", "category": "${CAT_LIST}", "color": "main color, 1-2 words", ${LOOK_FIELDS}, ` +
  '"box_2d": [ymin, xmin, ymax, xmax]} with box_2d normalized to 0-1000.';

const CUTOUT_PROMPT =
  "Give the segmentation mask for the main clothing item, shoe or accessory in this photo. " +
  'Output a JSON list with one entry containing the 2D bounding box in the key "box_2d" ' +
  '(normalized to 0-1000), the segmentation mask in the key "mask", and a text label in the key "label".';

// How each kind of piece is posed, so the result lines up with the model in the app
// (standing straight, facing forward, arms down).
const GHOST = "shown as if worn by an invisible person (a ghost-mannequin product photo) who stands straight and faces the camera";
const FIT_POSES = {
  Tops: `${GHOST}, arms hanging straight down close to the sides`,
  Jackets: `${GHOST}, arms hanging straight down close to the sides, the jacket closed`,
  Dresses: `${GHOST}, arms hanging straight down close to the sides, the skirt hanging naturally`,
  Bottoms: `${GHOST}, legs straight and slightly apart, the waistband level at the top`,
  Shoes: "as the pair standing side by side, toes pointing at the camera, seen straight from the front at ground level",
  Accessories: "laid flat and straightened, seen from the front",
};

// A front-facing version of the piece that fits the model. A magenta background is
// used for green clothes so the green screen does not eat the clothing.
const fitPrompt = (category, bg) =>
  `Make a clean e-commerce product photo of the main clothing item in this photo, ${FIT_POSES[category] || FIT_POSES.Tops}. ` +
  "Perfectly front-on and symmetrical, not tilted, rotated or folded. Keep its real colors, fabric, print, logos and details. " +
  "Do not show any person, skin, hands, head, mannequin, hanger, furniture or other items. " +
  "The item is fully visible, centered, and fills most of the image height. " +
  `Use a solid pure ${bg === "magenta" ? "magenta (#FF00FF)" : "bright green (#00FF00)"} background ` +
  "with no shadows, no reflections, no text and no watermark.";

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

// Image editing needs a paid Google key (billing turned on). Off unless ENABLE_FLATTEN = yes.
async function askGeminiImage(env, prompt, image, mime) {
  const model = env.FLATTEN_MODEL || "gemini-3.1-flash-image-preview";
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      signal: AbortSignal.timeout(60000),
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: image } }] }],
        generationConfig: { responseModalities: ["IMAGE"] },
      }),
    }
  );
  if (!res.ok) throw new Error("Image request failed " + res.status);
  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  const found = parts.find((p) => p.inlineData?.data || p.inline_data?.data);
  const d = found?.inlineData ?? found?.inline_data;
  if (!d?.data) throw new Error("No image returned");
  return { image: d.data, mime: d.mimeType ?? d.mime_type ?? "image/png" };
}

async function askGemini(env, prompt, image, mime = "image/jpeg", model = MODEL) {
  const parts = [{ text: prompt }];
  if (image) parts.push({ inline_data: { mime_type: mime, data: image } });
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      signal: AbortSignal.timeout(25000), // give up after 25 seconds instead of loading forever
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { responseMimeType: "application/json", thinkingConfig: { thinkingLevel: "low" } },
      }),
    }
  );
  if (!res.ok) throw new Error("AI request failed " + res.status);
  const data = await res.json();
  return JSON.parse(data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "");
}

const norm = (n) => Math.min(1, Math.max(0, Number(n) / 1000));
const cat = (c) => (CATEGORIES.includes(c) ? c : null);
const pick = (v, list, d) => (list.includes(v) ? v : d);
const hexc = (v, d) => (/^#[0-9a-fA-F]{6}$/.test(String(v)) ? String(v) : d);
const look = (e) => ({
  hex: hexc(e.hex, "#9E9AA8"),
  hex2: hexc(e.hex2, hexc(e.hex, "#9E9AA8")),
  pattern: pick(e.pattern, ["solid", "stripes", "checks", "dots"], "solid"),
  sleeves: pick(e.sleeves, ["none", "short", "long"], "short"),
  length: pick(e.length, ["short", "regular", "long"], "regular"),
  neckline: pick(e.neckline, ["round", "v", "collar"], "round"),
  bottomType: pick(e.bottom_type, ["pants", "shorts", "skirt"], "pants"),
});
const clean = (v, n) => String(v ?? "").replace(/[\r\n]+/g, " ").slice(0, n);
const cleanItems = (arr, max = 150) => // up to 150 closet pieces are sent to the stylist
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
        const note = clean(body.note, 300); // the occasion note plus today's weather
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

      const mime = ["image/jpeg", "image/png", "image/webp"].includes(body.mime) ? body.mime : "image/jpeg";

      if (body.mode === "flatten") {
        if (env.ENABLE_FLATTEN !== "yes") return reply({ error: "Flat photos are turned off" }, 403);
        const prompt = fitPrompt(cat(body.category) || "Tops", body.bg === "magenta" ? "magenta" : "green");
        return reply(await askGeminiImage(env, prompt, image, mime));
      }

      if (body.mode === "cutout") {
        // Set a CUTOUT_MODEL variable in Cloudflare to use a different model just for cutouts.
        const out = await askGemini(env, CUTOUT_PROMPT, image, mime, env.CUTOUT_MODEL || "gemini-flash-latest");
        const e = (Array.isArray(out) ? out : out.items ?? [out])[0];
        const b = e?.box_2d;
        const mask = typeof e?.mask === "string" ? e.mask.replace(/^data:image\/\w+;base64,/, "") : "";
        if (!Array.isArray(b) || b.length !== 4 || !mask) return reply({ error: "No outline found" }, 422);
        const [ymin, xmin, ymax, xmax] = b.map(norm);
        return reply({ box: [xmin, ymin, xmax, ymax], mask });
      }

      if (body.mode === "detect") {
        const out = await askGemini(env, DETECT_PROMPT, image, mime);
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
              ...look(e),
              box: [xmin, ymin, xmax, ymax],
            };
          })
          .filter(Boolean);
        return reply({ items });
      }

      const out = await askGemini(env, TAG_PROMPT, image, mime);
      return reply({ name: clean(out.name, 40), category: cat(out.category), color: clean(out.color, 30), ...look(out) });
    } catch (err) {
      return reply({ error: "AI request failed", detail: String(err).slice(0, 200) }, 502);
    }
  },
};
