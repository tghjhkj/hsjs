# Set up the AI helper (free)

1. Get a Gemini key: go to https://aistudio.google.com, sign in, click "Get API key".
2. Make a free Cloudflare account at https://dash.cloudflare.com.
3. In Cloudflare: Workers & Pages > Create > Create Worker. Name it `muse-ai`, click Deploy,
   then "Edit code". Delete the sample code, paste in `index.js` from this folder, click Deploy.
4. In the Worker's Settings > Variables and Secrets, add a **Secret** named `GEMINI_API_KEY`
   and paste your key. Deploy again.
5. (Recommended) Add a plain variable `ALLOWED_ORIGIN` with your site address,
   e.g. `https://YOUR_USERNAME.github.io`, so other websites can't use your Worker from a browser.
6. Copy the Worker address (looks like `https://muse-ai.YOURNAME.workers.dev`) and paste it
   into `aiEndpoint` near the top of `lib/main.dart`. Commit the change.

Menu names in Cloudflare change from time to time, so they may look slightly different.

## Updating the Worker
When `index.js` changes (for example to add wardrobe scanning), open your Worker in Cloudflare,
click "Edit code", replace everything with the new `index.js`, and click Deploy.
Your secret and address stay the same.

## Flat photos (optional, needs a paid Google key)
"Make a flat photo" turns any photo of a piece of clothing (worn, hanging, at an angle) into a clean
flat picture. It uses Google's image model, which has no free tier, so billing must be on for your key.

1. In Google AI Studio, turn on billing for the project your key belongs to. Set a budget alert in
   Google Cloud so you see any spending early. Each image costs a few cents; check Google's pricing page.
2. In your Worker's Settings > Variables and Secrets, add a plain variable `ENABLE_FLATTEN` with the value `yes`.
3. Redeploy the Worker.

Delete or change `ENABLE_FLATTEN` to turn it off. Anyone who knows your Worker address could call it,
so don't share the address. Optional: set `FLATTEN_MODEL` to use a different image model.
If the photo shows a person, the photo is sent to Google's image model; the prompt tells it to ignore them.
