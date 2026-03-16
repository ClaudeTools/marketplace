import Parser from "tree-sitter";
import TypeScriptLang from "tree-sitter-typescript";
import JavaScriptLang from "tree-sitter-javascript";

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

type SupportedLanguage = "typescript" | "tsx" | "javascript" | "jsx";

const parsers = new Map<SupportedLanguage, Parser>();

function getParser(language: SupportedLanguage): Parser {
  let parser = parsers.get(language);
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
  }
  parsers.set(language, parser);
  return parser;
}

export function detectLanguage(filePath: string): SupportedLanguage | null {
  if (filePath.endsWith(".ts")) return "typescript";
  if (filePath.endsWith(".tsx")) return "tsx";
  if (filePath.endsWith(".js") || filePath.endsWith(".mjs") || filePath.endsWith(".cjs")) return "javascript";
  if (filePath.endsWith(".jsx")) return "jsx";
  return null;
}

export function parseFile(source: string, language: SupportedLanguage): ParseResult {
  const parser = getParser(language);
  const tree = parser.parse(source);
  const root = tree.rootNode;

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
      // export { foo } from './bar' — the source is on the export_statement
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
  // lexical_declaration contains variable_declarator children
  const declarator = node.namedChildren.find(
    (c: Parser.SyntaxNode) => c.type === "variable_declarator"
  );
  if (!declarator) return null;

  const nameNode = declarator.childForFieldName("name");
  if (!nameNode) return null;

  const value = declarator.childForFieldName("value");
  const typeAnnotation = declarator.childForFieldName("type");

  // Detect if it's an arrow function
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

  // Walk import clause to find named imports
  for (let i = 0; i < node.namedChildCount; i++) {
    const child = node.namedChild(i);
    if (!child) continue;

    if (child.type === "import_clause") {
      for (let j = 0; j < child.namedChildCount; j++) {
        const importChild = child.namedChild(j);
        if (!importChild) continue;

        if (importChild.type === "identifier") {
          // Default import
          symbols.push(importChild.text);
        } else if (importChild.type === "named_imports") {
          // { foo, bar as baz }
          for (let k = 0; k < importChild.namedChildCount; k++) {
            const specifier = importChild.namedChild(k);
            if (specifier?.type === "import_specifier") {
              const name = specifier.childForFieldName("name");
              if (name) symbols.push(name.text);
            }
          }
        } else if (importChild.type === "namespace_import") {
          // * as ns
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

  // export { foo, bar } from './baz'
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
