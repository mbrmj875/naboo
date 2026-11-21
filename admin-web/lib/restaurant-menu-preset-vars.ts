export function presetCssVars(preset: string): Record<string, string> {
  const chromeOf: Record<string, string> = {
    classic: "photo-stack",
    modern: "app-grid",
    dark: "editorial",
    cafe: "paper-list",
    elegant: "magazine",
    minimal: "split-row",
    royal: "menu-board",
    garden: "soft-cards",
    ocean: "side-rail",
    bazaar: "banner-menu",
    thaiQr: "hero-cover",
    foodOrder: "compact-tiles",
    steakhouse: "cover-then-list",
    sushiBar: "paper-list",
    pizzeria: "soft-cards",
    bakery: "cover-then-list",
    juiceBar: "banner-menu",
    fineDining: "menu-board",
    streetFood: "split-row",
    veganGreen: "story-cards",
    dessertPastel: "soft-cards",
    smokeBbq: "hero-cover",
    mediterranean: "side-rail",
    lacquerRed: "magazine",
    pastaHouse: "photo-stack",
    brunchAir: "story-cards",
    nightMarket: "banner-menu",
    mezzeTable: "menu-board",
    dockSeafood: "paper-list",
    neonNight: "compact-tiles",
  };
  const chrome = chromeOf[preset] ?? "photo-stack";

  const base: Record<string, string> = {
    "--rst-radius-card": "8px",
    "--rst-shadow-card": "none",
    "--rst-font-size-body": "15px",
    "--rst-font-size-display": "28px",
    "--rst-image-aspect": "4 / 3",
    "--rst-button-radius": "8px",
    "--rst-chrome": chrome,
  };

  switch (chrome) {
    case "app-grid":
      return {
        ...base,
        "--rst-radius-card": "16px",
        "--rst-shadow-card": "0 4px 12px rgba(0,0,0,.08)",
        "--rst-image-aspect": "1 / 1",
        "--rst-button-radius": "9999px",
      };
    case "soft-cards":
      return {
        ...base,
        "--rst-radius-card": "18px",
        "--rst-shadow-card": "0 10px 28px rgba(0,0,0,.12)",
        "--rst-image-aspect": "1 / 1",
        "--rst-button-radius": "9999px",
      };
    case "compact-tiles":
      return {
        ...base,
        "--rst-radius-card": "12px",
        "--rst-shadow-card": "0 2px 8px rgba(0,0,0,.12)",
        "--rst-font-size-body": "13px",
        "--rst-image-aspect": "1 / 1",
        "--rst-button-radius": "9999px",
      };
    case "editorial":
    case "menu-board":
      return {
        ...base,
        "--rst-radius-card": "0px",
        "--rst-font-size-display": "32px",
        "--rst-button-radius": "0px",
      };
    case "magazine":
      return {
        ...base,
        "--rst-radius-card": "0px",
        "--rst-font-size-display": "30px",
        "--rst-image-aspect": "3 / 4",
        "--rst-button-radius": "0px",
      };
    case "paper-list":
    case "split-row":
      return {
        ...base,
        "--rst-radius-card": "10px",
        "--rst-image-aspect": "1 / 1",
        "--rst-button-radius": "9999px",
      };
    case "story-cards":
      return {
        ...base,
        "--rst-radius-card": "14px",
        "--rst-image-aspect": "3 / 4",
        "--rst-button-radius": "9999px",
      };
    case "hero-cover":
    case "cover-then-list":
      return {
        ...base,
        "--rst-image-aspect": "16 / 9",
        "--rst-button-radius": "8px",
      };
    case "side-rail":
      return {
        ...base,
        "--rst-radius-card": "12px",
        "--rst-image-aspect": "1 / 1",
      };
    case "banner-menu":
      return {
        ...base,
        "--rst-radius-card": "10px",
        "--rst-shadow-card": "0 2px 10px rgba(0,0,0,.06)",
        "--rst-image-aspect": "4 / 3",
      };
    case "photo-stack":
    default:
      return {
        ...base,
        "--rst-radius-card": "6px",
        "--rst-font-size-display": "32px",
      };
  }
}
