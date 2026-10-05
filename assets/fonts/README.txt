Шрифты проекта (все под SIL Open Font License 1.1, свободно для игр и веб-публикации).

NotoSans-Regular.ttf, NotoSansSymbols-Regular.ttf, NotoSansSymbols2-Regular.ttf, NotoSansMath-Regular.ttf
  — https://github.com/notofonts/notofonts.github.io (fonts/NotoSans*/hinted/ttf)
NotoEmoji.ttf (монохромный, variable)
  — https://github.com/google/fonts (ofl/notoemoji)

Подключены в theme/NeonTheme.tres как default_font (FontVariation): основной Noto Sans,
а значки (шахматные фигуры, стрелки, эмодзи, ∞ ≈ ≤ ≥) берутся из остальных по цепочке fallbacks.
Нужны для веб-сборки: в браузере системного fallback нет, без этих файлов значки превращаются в квадраты.
Проверка покрытия — в scripts/tools/audit_ui.gd (_scan_glyphs).
