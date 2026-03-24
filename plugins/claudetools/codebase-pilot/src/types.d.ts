declare module "tree-sitter-typescript" {
  import type { Language } from "tree-sitter";
  const languages: {
    typescript: Language;
    tsx: Language;
  };
  export default languages;
}

declare module "tree-sitter-javascript" {
  import type { Language } from "tree-sitter";
  const language: Language;
  export default language;
}

declare module "tree-sitter-python" {
  import type { Language } from "tree-sitter";
  const language: Language;
  export default language;
}
