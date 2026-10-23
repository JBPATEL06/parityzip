---
name: yaru-ui-guidelines
description: UI and UX rules for ParityZip - Ubuntu Yaru theme, the three-tab layout (Protect, Verify, Repair), wording, states, progress and error patterns, dark mode and window-size behaviour. Use this skill whenever you create or change any screen, widget, theme, text label, dialog, layout or visual state in the ParityZip app.
---

# ParityZip UI guidelines

References to consult (do not copy blindly; check current docs):
- yaru.dart (official Flutter Yaru theme and widgets): https://github.com/ubuntu/yaru.dart - live demo: https://ubuntu.github.io/yaru.dart/
- GNOME Human Interface Guidelines (spacing, dialogs, feedback patterns).

## Theme
- Wrap the app in `YaruTheme` and pass `yaru.theme` / `yaru.darkTheme` to `MaterialApp` so it follows the system light/dark mode and accent colour.
- Use theme colours and text styles only. No hard-coded colours except semantic success/error taken from the theme.

## Structure
- One window, three tabs: **Protect**, **Verify**, **Repair**.
- Each tab: inputs at the top, one primary action button, then a progress card, then an expandable log panel (collapsed by default, monospace, selectable, "Copy log" button).
- A dismissible banner at the top of the window if `7z` or `par2` is missing: name the missing tool and show the install command in selectable text with a Copy button.

## Protect tab (M2/M3)
Drop zone plus "Add files" and "Add folder" buttons; list of selected items with remove buttons; output folder; archive name; compression level (Fast / Normal / Maximum, default Normal); recovery data slider 5-30% default 10 with the label "Recovery data: 10%" and a hint "Roughly this much damage can be repaired"; button "Create protected archive".

## Verify and Repair tabs (M4)
Choose a `.par2` file (or drop it); button "Verify" / "Repair". Result card with one of: OK (check icon), Damaged but repairable, Damaged and cannot be repaired, Error. Each result says what to do next in one sentence. Offer "Open folder" (use `xdg-open` with an argument list).

## States (every action)
- Idle: primary button enabled only when inputs are valid; disabled buttons explain why (tooltip or helper text).
- Running: inputs disabled, progress bar (determinate if percent known, otherwise indeterminate), Cancel button.
- Success: summary (files, sizes, output paths) and Open folder.
- Failure: plain-English message, next step, log still available.

## Wording
- Sentence case, short, no jargon in primary text: say "recovery data" and mention "PAR2" only in secondary text.
- Errors never show raw exceptions as the main message; put them in the log.

## Layout and accessibility
- Minimum window about 800x600 must produce no RenderFlex overflow warnings; content scrolls when tall.
- Use tooltips on icon-only buttons. Keep contrast readable in both themes. Everything usable by keyboard (Tab order sensible, Enter on the primary action).
- Do not add animations beyond the defaults.
