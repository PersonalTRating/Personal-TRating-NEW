# CoachCards motion film brand kit

Refreshed 14 Nov 2026 from the production site https://www.coachcards.co.uk/. Pages checked at desktop (1440px) and mobile (375px) widths:

- Homepage `/`: desktop and mobile
- Find a Trainer `/find-a-trainer/`: desktop and mobile
- Tracy Gibson's profile `/trainers/ed71661a-2515-4df0-b0fe-0f486968d104/`: desktop and mobile
- Paul Davies's profile `/trainers/639b7020-9f0a-4ff4-b352-8169d1d65068/`: desktop
- For Trainers `/for-trainers/`: desktop and mobile
- Sign-up `/signup/`: desktop

Mobile uses the same images, fonts and colours as desktop. No page loads an image that isn't already in the kit, apart from trainers' own photos, which are left out on purpose.

`contact-sheet.png` shows everything below.

## production/ — what the live site serves

Colours were read from the computed styles of visible elements on those three pages. Images were downloaded from the URLs the pages request, at the size the server sends them.

### Colours

| Role | Hex | Where it's used |
| --- | --- | --- |
| Page background | #FFFFFF | Body, nav, filters (all pages) |
| Light panel | #F7F9F7 | Homepage cards and panels |
| Light section | #F4F6F4 | Homepage section, profile body |
| Dark hero / footer | #111311 | Homepage hero, Find a Trainer hero, geo nav, footer |
| Dark section | #0D1A0E | Homepage "about" and dark sections |
| Leaderboard | #0A130B | Homepage leaderboard section, profile footer |
| Find a Trainer list | #0A120B | Trainer list background |
| Profile hero | #090C09 | Trainer profile hero |
| Dark cards | #081009 (88–95%), #040A05 (97%) | Leaderboard and trainer cards |
| Text | #111311 | Primary text on light backgrounds |
| Text on dark | #FFFFFF (100%, 55%, 30%) | Headlines and subtext on dark |
| Muted text | #8A8F8A, #7A8F7C, #5A6B5C, #6B7F6D | Nav links, captions, chips, profile labels |
| **Accent** | **#3AB54A** | Buttons, CTAs, rank numbers, card borders, icons, pills (12–15% fill) |
| Accent dark | #2A9438 | BMP values and checkmarks on the profile |
| Glow green | #7DE88A | BMP chip text on the homepage hero |
| Green tint | #EAF7EC | BMP tier cards and pills |
| Borders | #E0E8E1, #C3E6C8 | Cards and chips; review cards |
| Location pin | #E85D4A | Map pin icons |
| Coaching-type pill | #3C78DC (12% fill) | "Online & in person" pill |
| Rating bar | #FFB800 | Profile rating breakdown bars |
| Icon accents | #0EA5E9 sky, #8B5CF6 violet, #F87171 red, #F59E0B amber | Outline feature icons on For Trainers (amber and red also on the homepage) |

Gradients:

- Profile panel: `135deg, #0D1A0E 0% → #1A3D1E 60% → #2A5A30 100%`
- Sign-up side panel: `160deg, #0D1A0E → #1A3D1E 55% → #2A5A30` (the sign-up page background is #F7F9F7)
- Profile card: `160deg, #091909 → #050C06`
- For Trainers glow: `radial, rgba(58,181,74,.18) → transparent 65%`
- Homepage hero overlay: `108deg, rgba(8,18,10,.75) → rgba(8,18,10,.52) 45% → rgba(8,18,10,.20)`
- Find a Trainer glow: `radial, rgba(58,181,74,.14) → transparent 68%`

Not brand colours:

- Each trainer profile has a two-tone theme the trainer picks. Tracy Gibson's is yellow (#FFFC31, #C7C526, #FFFEA2); Paul Davies's is navy (#212D53, #2A3A6A, #AABCE0, #1A4B6B). Everything else on a profile, like the hero (#090C09), green buttons, BMP panel and footer, is the same for every trainer.
- The homepage BMP tier cards also use pastel tints (#E0F2FE, #CCFBF1, #FEF3C7, #EDE9FE).

### Fonts (`production/fonts`, static TTF from Google Fonts, OFL)

- **Playfair Display** 700 and 900: headlines
- **Manrope** 400, 500, 600, 700 and 800: body and UI. The profile asks for weight 900, but Manrope's heaviest weight is 800, so browsers render 800. Italic Manrope on the site is slanted by the browser; there's no real italic file.

### Images and logos

| File | Served size | Used on |
| --- | --- | --- |
| `img/hero-bg.webp` | 1536×1024 | Homepage hero background |
| `img/leaderboard-bg.webp` | 1672×941 | Homepage leaderboard background |
| `img/og-social.png` | 1200×630 | Social share image (homepage, Find a Trainer) |
| `img/coachcards-founder-badge.png` | 257×61 | Founder badge on cards and profile |
| `img/bmp-frames/bmp-000…100.webp` | 1000×410 ×101 | BMP dumbbell; each page shows the frame matching a score |
| `logos/cc-logo.png` | 400×400 | Nav logo (all pages) |
| `logos/apple-touch-icon.png` | 180×180 | Touch icon |
| `logos/favicon.png` | 64×64 | Favicon |

The live pages also show real trainers' profile photos and post images. These are deliberately left out of the kit; the film uses the supplied trainer photos below instead.

**Logo to use:** the circular CC mark (`logos/cc-logo.png`) is the only current logo. 400×400 is the agreed final size for the film; keep it to small placements such as a corner logo or end-card badge rather than filling the frame. The old dumbbell "CoachCards" wordmark (76% / 96% plates, green rounded frame, still in the repo as `public/images/logo.png` and on the Desktop as `CoachCards Logo.png`) is retired; don't use it in the film.

### Repo originals checked

The task allowed adding a higher-resolution original from the repo only if it matched the live file. None qualified:

- `public/images/hero-bg.png` is the same size as the live file and is an **older version**: the shirt says "TRAINER" where the live image has the CC logo. Excluded.
- `public/images/cc-logo.webp` (1254px) **doesn't match** the live `cc-logo.png`: it has a square black background instead of a transparent circle. Excluded.
- `CoachCards_BMPv3_101_Frame_Assets_95Plus.zip`: its frames are the same 1000×410 size as the live ones, with 100 of 101 byte-identical. Nothing higher-resolution.

## supplied/ — your files, not served by the live site

**Trainer photos: use these for every trainer shot in the film.**

- `trainer/trainer-portrait.webp` (687×1024): front-facing portrait in a gym, wearing a CC tee
- `trainer/trainer-reference-sheet.webp` (1024×572): four views of the same character (close-up, three-quarter, profile, full body) on a plain background, for keeping him consistent across shots

From `CoachCards-Motion-Graphics.zip`:
- `demo-visuals/`: gym hero, Discover poster, gym-goer character reference, trainer profile redesign, ranking card. The redesign and ranking card are design mockups.
- `tool-logos/`: `claude.svg` and `openai.svg` (one-colour, from Simple Icons). Use the OpenAI mark for the ChatGPT step. These are the only two tools shown in the film; no other tool logos are needed.
- `film-fonts/`: IBM Plex Mono 500 for counters and Playfair Display 400 for chatbot replies. Both are choices made for the film and aren't used on the live site.

The orange palette from the zip (accent #FF4D17) is another film-only option and doesn't appear on the live site.
