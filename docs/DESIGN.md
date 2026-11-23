# Design System: EventFlow Practice 05

Generated following `skills/stitch-skills/plugins/stitch-utilities/skills/taste-design/SKILL.md` and §9 of the project specification.

## 1. Visual Theme & Atmosphere
- **Mood:** Warm, editorial event-tech product — like a physical festival pass and a calm control room combined.
- **Density:** Daily App Balanced (5/10) for Participant & Controller; Cockpit Dense (7/10) for Organizer dashboard with tabular monospace numbers.
- **Anti-patterns banned:** No AI purple/neon gradients, no pure `#000000`, no `Inter` font, no emojis in UI chrome, no 3-column generic feature cards, no default Material blue/purple look.

## 2. Color Palette & Roles (in `lib/design/tokens.dart`)
- **Warm Paper** (`#FAF7F2`) — Primary scaffold background
- **Pure Card** (`#FFFFFF`) — Elevated surface for ticket cards, event cards, and forms
- **Warm Stone** (`#F1ECE2`) — Subtle secondary surface, chip backgrounds, table headers
- **Deep Ink** (`#1C1B18`) — Primary text and high-contrast headings
- **Muted Slate** (`#635F57`) — Secondary text, metadata, timestamps
- **Hairline Border** (`#E4DDD0`) — 1px structural dividers and card outlines
- **Event Emerald** (`#1F9D6B`) — Primary brand accent (CTAs, active nav, `ACCEPTED` / `ISSUED` positive state)
- **Emerald Tint** (`#E7F6EF`) — Soft positive badge background
- **Coral Alert** (`#D94F3D`) — Destructive actions, `CANCELLED`, `INVALID`, `WRONG_EVENT`
- **Coral Tint** (`#FCECE9`) — Soft error badge background
- **Amber Caution** (`#C97A16`) — `ALREADY_USED`, `CLOSED`, `SOLD_OUT`, offline/pending states
- **Amber Tint** (`#FDF3E3`) — Soft warning badge background

## 3. Typography Rules
- **Display / Headings:** `Outfit` (track-tight `-0.02em`, weight `600–700`)
- **Body:** `Plus Jakarta Sans` (relaxed leading `1.45`, min `14px`)
- **Mono:** `JetBrains Mono` (ticket codes `EF-0042`, capacity counters, server timestamps)

## 4. Component Stylings
- **QR Ticket Card:** Perforated horizontal divider with semicircular side cutouts, monospace ticket code, high-contrast QR on `#FFFFFF` quiet zone, explicit text+icon status pill (never color-only).
- **Buttons:** 48px minimum touch target on mobile, 12px radius, flat tactile fill with subtle press state.
- **Adaptive Navigation:**
  - `< 768 px` (360 px mobile): Bottom `NavigationBar` + single-column cards, zero horizontal scroll.
  - `>= 768 px` (1280 px desktop/web): Left `NavigationRail` + multi-column workspace / `DataTable`.
