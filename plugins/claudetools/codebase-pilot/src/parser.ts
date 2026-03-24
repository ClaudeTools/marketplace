import Parser from "tree-sitter";
import TypeScriptLang from "tree-sitter-typescript";
import JavaScriptLang from "tree-sitter-javascript";
import PythonLang from "tree-sitter-python";
import path from "node:path";
import fs from "node:fs";

const { typescript: TSLang, tsx: TSXLang } = TypeScriptLang;

export interface ExtractedSymbol {
  name: string;
  kind: SymbolKind;
  line: number;
  endLine: number;
  signature: string | null;
  exported: boolean;
  children: ExtractedSymbol[];
}

export interface ExtractedImport {
  source: string;
  symbols: string[];
}

export interface ParseResult {
  symbols: ExtractedSymbol[];
  imports: ExtractedImport[];
}

export type SymbolKind =
  | "function"
  | "class"
  | "interface"
  | "type"
  | "enum"
  | "variable"
  | "method"
  | "property";

export type SupportedLanguage =
  | "typescript" | "tsx" | "javascript" | "jsx" | "python"
  | "go" | "rust" | "java" | "kotlin" | "ruby" | "c_sharp"
  | "php" | "swift" | "c" | "cpp" | "bash";

// Native languages use the fast native tree-sitter path
const NATIVE_LANGUAGES = new Set<SupportedLanguage>(["typescript", "tsx", "javascript", "jsx", "python"]);

const nativeParsers = new Map<SupportedLanguage, Parser>();

function getNativeParser(language: SupportedLanguage): Parser {
  let parser = nativeParsers.get(language);
  if (parser) return parser;

  parser = new Parser();
  switch (language) {
    case "typescript":
      parser.setLanguage(TSLang);
      break;
    case "tsx":
      parser.setLanguage(TSXLang);
      break;
    case "javascript":
    case "jsx":
      parser.setLanguage(JavaScriptLang);
      break;
    case "python":
      parser.setLanguage(PythonLang);
      break;
  }
  nativeParsers.set(language, parser);
  return parser;
}

// ── Shared node interface for generic extractors ────────────────────
// Both native tree-sitter SyntaxNode and web-tree-sitter Node share this shape.
interface ASTNode {
  type: string;
  text: string;
  startPosition: { row: number; column: number };
  endPosition: { row: number; column: number };
  childCount: number;
  namedChildCount: number;
  child(index: number): ASTNode | null;
  namedChild(index: number): ASTNode | null;
  childForFieldName(fieldName: string): ASTNode | null;
  readonly namedChildren: ASTNode[];
}

// ── WASM support ────────────────────────────────────────────────────

// Lazy-loaded web-tree-sitter module types
type WasmParser = import("web-tree-sitter").Parser;
type WasmLanguage = import("web-tree-sitter").Language;

let WasmParserClass: typeof import("web-tree-sitter").Parser | null = null;
let wasmInitialized = false;
const wasmLanguageCache = new Map<string, WasmLanguage>();

async function initWasm(): Promise<typeof import("web-tree-sitter").Parser> {
  if (WasmParserClass && wasmInitialized) return WasmParserClass;
  const mod = await import("web-tree-sitter");
  WasmParserClass = mod.Parser;
  await WasmParserClass.init();
  wasmInitialized = true;
  return WasmParserClass;
}

async function getWasmLanguage(language: SupportedLanguage): Promise<WasmLanguage> {
  const cached = wasmLanguageCache.get(language);
  if (cached) return cached;

  const grammarPath = path.join(__dirname, "..", "grammars", `tree-sitter-${language}.wasm`);
  if (!fs.existsSync(grammarPath)) {
    throw new Error(`WASM grammar not found: ${grammarPath}`);
  }

  await initWasm();
  const { Language } = await import("web-tree-sitter");
  const lang = await Language.load(grammarPath);
  wasmLanguageCache.set(language, lang);
  return lang;
}

// ── Language detection ──────────────────────────────────────────────

export function detectLanguage(filePath: string): SupportedLanguage | null {
  if (filePath.endsWith(".ts")) return "typescript";
  if (filePath.endsWith(".tsx")) return "tsx";
  if (filePath.endsWith(".js") || filePath.endsWith(".mjs") || filePath.endsWith(".cjs")) return "javascript";
  if (filePath.endsWith(".jsx")) return "jsx";
  if (filePath.endsWith(".py")) return "python";
  if (filePath.endsWith(".go")) return "go";
  if (filePath.endsWith(".rs")) return "rust";
  if (filePath.endsWith(".java")) return "java";
  if (filePath.endsWith(".kt") || filePath.endsWith(".kts")) return "kotlin";
  if (filePath.endsWith(".rb")) return "ruby";
  if (filePath.endsWith(".cs")) return "c_sharp";
  if (filePath.endsWith(".php")) return "php";
  if (filePath.endsWith(".swift")) return "swift";
  if (filePath.endsWith(".c") || filePath.endsWith(".h")) return "c";
  if (filePath.endsWith(".cpp") || filePath.endsWith(".hpp") || filePath.endsWith(".cc") || filePath.endsWith(".cxx")) return "cpp";
  if (filePath.endsWith(".sh") || filePath.endsWith(".bash")) return "bash";
  return null;
}

// ── Main parse entry point (now async) ──────────────────────────────

export async function parseFile(source: string, language: SupportedLanguage): Promise<ParseResult> {
  if (NATIVE_LANGUAGES.has(language)) {
    return parseNative(source, language);
  }
  return parseWasm(source, language);
}

// ── Native parsing (unchanged logic) ────────────────────────────────

function parseNative(source: string, language: SupportedLanguage): ParseResult {
  const parser = getNativeParser(language);
  const tree = parser.parse(source);
  const root = tree.rootNode;

  if (language === "python") {
    return parsePythonFile(root);
  }

  const symbols: ExtractedSymbol[] = [];
  const imports: ExtractedImport[] = [];

  for (let i = 0; i < root.childCount; i++) {
    const node = root.child(i);
    if (!node) continue;

    const isExported = node.type === "export_statement";
    const targetNode = isExported
      ? node.childForFieldName("declaration") ?? node.namedChildren[0]
      : node;

    if (!targetNode) continue;

    // Handle imports
    if (node.type === "import_statement") {
      const imp = extractImport(node);
      if (imp) imports.push(imp);
      continue;
    }

    // Handle export { ... } from '...' (re-exports)
    if (isExported && !targetNode) {
      const source = node.childForFieldName("source");
      if (source) {
        const imp = extractReexport(node, source);
        if (imp) imports.push(imp);
      }
      continue;
    }

    const extracted = extractSymbol(targetNode, isExported);
    if (extracted) {
      symbols.push(extracted);
    }
  }

  return { symbols, imports };
}

// ── WASM parsing ────────────────────────────────────────────────────

async function parseWasm(source: string, language: SupportedLanguage): Promise<ParseResult> {
  const ParserClass = await initWasm();
  const lang = await getWasmLanguage(language);

  const parser = new ParserClass();
  parser.setLanguage(lang);
  const tree = parser.parse(source);

  if (!tree) {
    parser.delete();
    return { symbols: [], imports: [] };
  }

  try {
    return extractGenericSymbols(tree.rootNode as unknown as ASTNode);
  } finally {
    tree.delete();
    parser.delete();
  }
}

// ── Generic symbol extractor for WASM-parsed languages ──────────────

// Node types that commonly represent functions across languages
const FUNCTION_NODE_TYPES = new Set([
  "function_declaration", "function_definition", "function_item",
  "method_declaration", "method_definition", "func_literal",
  "function_signature_item",
]);

// Node types for classes/structs
const CLASS_NODE_TYPES = new Set([
  "class_declaration", "class_definition", "struct_item",
  "type_declaration", "struct_declaration", "struct_specifier",
  "class_specifier",
]);

// Node types for interfaces/traits/protocols
const INTERFACE_NODE_TYPES = new Set([
  "interface_declaration", "trait_item", "protocol_declaration",
]);

// Node types for variables/constants
const VARIABLE_NODE_TYPES = new Set([
  "variable_declaration", "const_declaration", "const_item",
  "short_var_declaration", "assignment", "static_item",
  "let_declaration",
]);

// Node types for imports
const IMPORT_NODE_TYPES = new Set([
  "import_declaration", "use_declaration", "require",
  "import_statement", "include_directive",
]);

function extractGenericSymbols(root: ASTNode): ParseResult {
  const symbols: ExtractedSymbol[] = [];
  const imports: ExtractedImport[] = [];

  function walk(node: ASTNode, depth: number): void {
    // Only process top-level and one level deep (class members)
    if (depth > 1) return;

    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (!child) continue;
      const type: string = child.type;

      if (FUNCTION_NODE_TYPES.has(type)) {
        const sym = extractGenericFunction(child);
        if (sym) symbols.push(sym);
      } else if (CLASS_NODE_TYPES.has(type)) {
        const sym = extractGenericClass(child);
        if (sym) symbols.push(sym);
      } else if (INTERFACE_NODE_TYPES.has(type)) {
        const sym = extractGenericInterface(child);
        if (sym) symbols.push(sym);
      } else if (VARIABLE_NODE_TYPES.has(type)) {
        const sym = extractGenericVariable(child);
        if (sym) symbols.push(sym);
      } else if (IMPORT_NODE_TYPES.has(type)) {
        const imp = extractGenericImport(child);
        if (imp) imports.push(imp);
      } else if (type === "impl_item" || type === "impl_declaration") {
        // Rust impl blocks — extract methods as children
        walk(child, depth);
      } else if (type === "declaration_list" || type === "block") {
        // Some languages wrap top-level in a block
        if (depth === 0) walk(child, depth);
      }
    }
  }

  walk(root, 0);
  return { symbols, imports };
}

function getNameText(node: ASTNode): string | null {
  // Try common field names for the declaration's name
  const nameNode = node.childForFieldName("name")
    ?? node.childForFieldName("declarator");
  if (nameNode) {
    // For C/C++ declarators, the name might be nested
    if (nameNode.type === "function_declarator" || nameNode.type === "pointer_declarator") {
      const inner = nameNode.childForFieldName("declarator");
      return inner?.text ?? nameNode.text;
    }
    return nameNode.text;
  }
  return null;
}

function extractGenericFunction(node: ASTNode): ExtractedSymbol | null {
  const name = getNameText(node);
  if (!name) return null;

  const params = node.childForFieldName("parameters")
    ?? node.childForFieldName("formal_parameters");
  let sig = name;
  if (params) sig += params.text.length < 120 ? params.text : "(...)";

  return {
    name,
    kind: "function",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported: true, // Conservative default for non-JS languages
    children: [],
  };
}

function extractGenericClass(node: ASTNode): ExtractedSymbol | null {
  const name = getNameText(node);
  if (!name) return null;

  const children: ExtractedSymbol[] = [];
  const body = node.childForFieldName("body")
    ?? node.childForFieldName("field_declaration_list");

  if (body) {
    for (let i = 0; i < body.childCount; i++) {
      const member = body.child(i);
      if (!member) continue;
      if (FUNCTION_NODE_TYPES.has(member.type)) {
        const m = extractGenericFunction(member);
        if (m) {
          m.kind = "method";
          m.exported = false;
          children.push(m);
        }
      }
    }
  }

  return {
    name,
    kind: "class",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: name,
    exported: true,
    children,
  };
}

function extractGenericInterface(node: ASTNode): ExtractedSymbol | null {
  const name = getNameText(node);
  if (!name) return null;

  return {
    name,
    kind: "interface",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: name,
    exported: true,
    children: [],
  };
}

function extractGenericVariable(node: ASTNode): ExtractedSymbol | null {
  const name = getNameText(node);
  if (!name || name.length > 80) return null;

  return {
    name,
    kind: "variable",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: node.text.replace(/\n/g, " ").slice(0, 120),
    exported: true,
    children: [],
  };
}

function extractGenericImport(node: ASTNode): ExtractedImport | null {
  const text = node.text;
  if (!text) return null;

  // Best-effort: extract the import path/module from the node text
  const pathMatch = text.match(/["']([^"']+)["']/);
  const source = pathMatch?.[1] ?? text.replace(/\n/g, " ").slice(0, 120);

  return { source, symbols: [] };
}

// ── Native TS/JS symbol extraction (unchanged) ─────────────────────

function extractSymbol(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  switch (node.type) {
    case "function_declaration":
    case "generator_function_declaration":
      return extractFunction(node, exported);
    case "class_declaration":
      return extractClass(node, exported);
    case "interface_declaration":
      return extractInterface(node, exported);
    case "type_alias_declaration":
      return extractTypeAlias(node, exported);
    case "enum_declaration":
      return extractEnum(node, exported);
    case "lexical_declaration":
    case "variable_declaration":
      return extractVariable(node, exported);
    default:
      return null;
  }
}

function extractFunction(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  const params = node.childForFieldName("parameters");
  const returnType = node.childForFieldName("return_type");
  const typeParams = node.childForFieldName("type_parameters");

  let sig = nameNode.text;
  if (typeParams) sig += typeParams.text;
  if (params) sig += params.text;
  if (returnType) sig += ": " + returnType.text.replace(/^:\s*/, "");

  return {
    name: nameNode.text,
    kind: "function",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported,
    children: [],
  };
}

function extractClass(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  const children: ExtractedSymbol[] = [];
  const body = node.childForFieldName("body");
  if (body) {
    for (let i = 0; i < body.namedChildCount; i++) {
      const member = body.namedChild(i);
      if (!member) continue;
      if (member.type === "method_definition") {
        const method = extractMethod(member);
        if (method) children.push(method);
      } else if (
        member.type === "public_field_definition" ||
        member.type === "property_definition"
      ) {
        const prop = extractProperty(member);
        if (prop) children.push(prop);
      }
    }
  }

  const typeParams = node.childForFieldName("type_parameters");
  let sig = nameNode.text;
  if (typeParams) sig += typeParams.text;

  return {
    name: nameNode.text,
    kind: "class",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported,
    children,
  };
}

function extractInterface(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  const typeParams = node.childForFieldName("type_parameters");
  let sig = nameNode.text;
  if (typeParams) sig += typeParams.text;

  const children: ExtractedSymbol[] = [];
  const body = node.childForFieldName("body");
  if (body) {
    for (let i = 0; i < body.namedChildCount; i++) {
      const member = body.namedChild(i);
      if (!member) continue;
      if (
        member.type === "property_signature" ||
        member.type === "method_signature"
      ) {
        const nameField = member.childForFieldName("name");
        if (nameField) {
          children.push({
            name: nameField.text,
            kind: member.type === "method_signature" ? "method" : "property",
            line: member.startPosition.row + 1,
            endLine: member.endPosition.row + 1,
            signature: member.text.replace(/\n/g, " ").slice(0, 120),
            exported: false,
            children: [],
          });
        }
      }
    }
  }

  return {
    name: nameNode.text,
    kind: "interface",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported,
    children,
  };
}

function extractTypeAlias(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  const typeParams = node.childForFieldName("type_parameters");
  const value = node.childForFieldName("value");

  let sig = nameNode.text;
  if (typeParams) sig += typeParams.text;
  if (value) {
    const valText = value.text;
    sig += " = " + (valText.length > 80 ? valText.slice(0, 80) + "..." : valText);
  }

  return {
    name: nameNode.text,
    kind: "type",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported,
    children: [],
  };
}

function extractEnum(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  return {
    name: nameNode.text,
    kind: "enum",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: nameNode.text,
    exported,
    children: [],
  };
}

function extractVariable(
  node: Parser.SyntaxNode,
  exported: boolean
): ExtractedSymbol | null {
  const declarator = node.namedChildren.find(
    (c: Parser.SyntaxNode) => c.type === "variable_declarator"
  );
  if (!declarator) return null;

  const nameNode = declarator.childForFieldName("name");
  if (!nameNode) return null;

  const value = declarator.childForFieldName("value");
  const typeAnnotation = declarator.childForFieldName("type");

  let kind: SymbolKind = "variable";
  if (value?.type === "arrow_function" || value?.type === "function") {
    kind = "function";
  }

  let sig = nameNode.text;
  if (typeAnnotation) {
    sig += ": " + typeAnnotation.text.replace(/^:\s*/, "");
  }
  if (kind === "function" && value) {
    const params = value.childForFieldName("parameters");
    const returnType = value.childForFieldName("return_type");
    sig = nameNode.text;
    if (params) sig += params.text;
    if (returnType) sig += ": " + returnType.text.replace(/^:\s*/, "");
  }

  return {
    name: nameNode.text,
    kind,
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported,
    children: [],
  };
}

function extractMethod(node: Parser.SyntaxNode): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  const params = node.childForFieldName("parameters");
  const returnType = node.childForFieldName("return_type");

  let sig = nameNode.text;
  if (params) sig += params.text;
  if (returnType) sig += ": " + returnType.text.replace(/^:\s*/, "");

  return {
    name: nameNode.text,
    kind: "method",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported: false,
    children: [],
  };
}

function extractProperty(node: Parser.SyntaxNode): ExtractedSymbol | null {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) return null;

  return {
    name: nameNode.text,
    kind: "property",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: node.text.replace(/\n/g, " ").slice(0, 120),
    exported: false,
    children: [],
  };
}

function extractImport(node: Parser.SyntaxNode): ExtractedImport | null {
  const sourceNode = node.childForFieldName("source");
  if (!sourceNode) return null;

  const source = sourceNode.text.replace(/^['"]|['"]$/g, "");
  const symbols: string[] = [];

  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (!child) continue;

    if (child.type === "import_clause") {
      for (let j = 0; j < child.namedChildCount; j++) {
        const importChild = child.namedChild(j);
        if (!importChild) continue;

        if (importChild.type === "identifier") {
          symbols.push(importChild.text);
        } else if (importChild.type === "named_imports") {
          for (let k = 0; k < importChild.namedChildCount; k++) {
            const specifier = importChild.namedChild(k);
            if (specifier?.type === "import_specifier") {
              const name = specifier.childForFieldName("name");
              if (name) symbols.push(name.text);
            }
          }
        } else if (importChild.type === "namespace_import") {
          const name = importChild.childForFieldName("name");
          if (name) symbols.push("* as " + name.text);
        }
      }
    }
  }

  return { source, symbols };
}

function extractReexport(
  node: Parser.SyntaxNode,
  sourceNode: Parser.SyntaxNode
): ExtractedImport | null {
  const source = sourceNode.text.replace(/^['"]|['"]$/g, "");
  const symbols: string[] = [];

  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (child?.type === "export_clause") {
      for (let j = 0; j < child.namedChildCount; j++) {
        const specifier = child.namedChild(j);
        if (specifier?.type === "export_specifier") {
          const name = specifier.childForFieldName("name");
          if (name) symbols.push(name.text);
        }
      }
    }
  }

  return { source, symbols };
}

// ── Python parsing ──────────────────────────────────────────────────

function parsePythonFile(root: Parser.SyntaxNode): ParseResult {
  const symbols: ExtractedSymbol[] = [];
  const imports: ExtractedImport[] = [];

  for (let i = 0; i < root.childCount; i++) {
    const node = root.child(i);
    if (!node) continue;

    switch (node.type) {
      case "function_definition":
        symbols.push(extractPythonFunction(node));
        break;
      case "class_definition":
        symbols.push(extractPythonClass(node));
        break;
      case "import_statement":
        imports.push(extractPythonImport(node));
        break;
      case "import_from_statement":
        imports.push(extractPythonFromImport(node));
        break;
      case "decorated_definition": {
        const inner = node.namedChildren.find(
          (c) => c.type === "function_definition" || c.type === "class_definition"
        );
        if (inner?.type === "function_definition") {
          symbols.push(extractPythonFunction(inner));
        } else if (inner?.type === "class_definition") {
          symbols.push(extractPythonClass(inner));
        }
        break;
      }
      case "expression_statement": {
        const expr = node.namedChildren[0];
        if (expr?.type === "assignment") {
          const left = expr.childForFieldName("left");
          if (left?.type === "identifier") {
            symbols.push({
              name: left.text,
              kind: "variable",
              line: node.startPosition.row + 1,
              endLine: node.endPosition.row + 1,
              signature: node.text.replace(/\n/g, " ").slice(0, 120),
              exported: true,
              children: [],
            });
          }
        }
        break;
      }
    }
  }

  return { symbols, imports };
}

function extractPythonFunction(node: Parser.SyntaxNode): ExtractedSymbol {
  const nameNode = node.childForFieldName("name")!;
  const params = node.childForFieldName("parameters");
  const returnType = node.childForFieldName("return_type");

  let sig = nameNode.text;
  if (params) sig += params.text;
  if (returnType) sig += " -> " + returnType.text;

  return {
    name: nameNode.text,
    kind: "function",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported: !nameNode.text.startsWith("_"),
    children: [],
  };
}

function extractPythonClass(node: Parser.SyntaxNode): ExtractedSymbol {
  const nameNode = node.childForFieldName("name")!;
  const children: ExtractedSymbol[] = [];

  const body = node.childForFieldName("body");
  if (body) {
    for (let i = 0; i < body.namedChildCount; i++) {
      const member = body.namedChild(i);
      if (!member) continue;
      if (member.type === "function_definition") {
        const methodName = member.childForFieldName("name");
        if (methodName) {
          const mParams = member.childForFieldName("parameters");
          const mReturn = member.childForFieldName("return_type");
          let mSig = methodName.text;
          if (mParams) mSig += mParams.text;
          if (mReturn) mSig += " -> " + mReturn.text;
          children.push({
            name: methodName.text,
            kind: "method",
            line: member.startPosition.row + 1,
            endLine: member.endPosition.row + 1,
            signature: mSig,
            exported: false,
            children: [],
          });
        }
      } else if (member.type === "decorated_definition") {
        const inner = member.namedChildren.find((c) => c.type === "function_definition");
        if (inner) {
          const methodName = inner.childForFieldName("name");
          if (methodName) {
            const mParams = inner.childForFieldName("parameters");
            const mReturn = inner.childForFieldName("return_type");
            let mSig = methodName.text;
            if (mParams) mSig += mParams.text;
            if (mReturn) mSig += " -> " + mReturn.text;
            children.push({
              name: methodName.text,
              kind: "method",
              line: inner.startPosition.row + 1,
              endLine: inner.endPosition.row + 1,
              signature: mSig,
              exported: false,
              children: [],
            });
          }
        }
      }
    }
  }

  const superclasses = node.childForFieldName("superclasses");
  let sig = nameNode.text;
  if (superclasses) sig += superclasses.text;

  return {
    name: nameNode.text,
    kind: "class",
    line: node.startPosition.row + 1,
    endLine: node.endPosition.row + 1,
    signature: sig,
    exported: !nameNode.text.startsWith("_"),
    children,
  };
}

function extractPythonImport(node: Parser.SyntaxNode): ExtractedImport {
  const symbols: string[] = [];
  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (child?.type === "dotted_name") {
      symbols.push(child.text);
    } else if (child?.type === "aliased_import") {
      const name = child.childForFieldName("name");
      if (name) symbols.push(name.text);
    }
  }
  return { source: symbols[0] ?? "", symbols };
}

function extractPythonFromImport(node: Parser.SyntaxNode): ExtractedImport {
  const moduleNode = node.childForFieldName("module_name");
  const source = moduleNode?.text ?? "";
  const symbols: string[] = [];

  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (child === moduleNode) continue;
    if (child?.type === "aliased_import") {
      const name = child.childForFieldName("name");
      if (name) symbols.push(name.text);
    } else if (child?.type === "dotted_name") {
      symbols.push(child.text);
    }
  }

  if (symbols.length === 0) {
    const match = node.text.match(/import\s+(.+)$/);
    if (match) {
      for (const name of match[1].split(",")) {
        const trimmed = name.trim().split(/\s+as\s+/)[0].trim();
        if (trimmed && trimmed !== "*") symbols.push(trimmed);
      }
    }
  }

  return { source, symbols };
}
