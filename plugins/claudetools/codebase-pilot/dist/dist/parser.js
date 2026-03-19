import Parser from "tree-sitter";
import TypeScriptLang from "tree-sitter-typescript";
import JavaScriptLang from "tree-sitter-javascript";
import PythonLang from "tree-sitter-python";
const { typescript: TSLang, tsx: TSXLang } = TypeScriptLang;
const parsers = new Map();
function getParser(language) {
    let parser = parsers.get(language);
    if (parser)
        return parser;
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
    parsers.set(language, parser);
    return parser;
}
export function detectLanguage(filePath) {
    if (filePath.endsWith(".ts"))
        return "typescript";
    if (filePath.endsWith(".tsx"))
        return "tsx";
    if (filePath.endsWith(".js") || filePath.endsWith(".mjs") || filePath.endsWith(".cjs"))
        return "javascript";
    if (filePath.endsWith(".jsx"))
        return "jsx";
    if (filePath.endsWith(".py"))
        return "python";
    return null;
}
export function parseFile(source, language) {
    const parser = getParser(language);
    const tree = parser.parse(source);
    const root = tree.rootNode;
    if (language === "python") {
        return parsePythonFile(root);
    }
    const symbols = [];
    const imports = [];
    for (let i = 0; i < root.childCount; i++) {
        const node = root.child(i);
        if (!node)
            continue;
        const isExported = node.type === "export_statement";
        const targetNode = isExported
            ? node.childForFieldName("declaration") ?? node.namedChildren[0]
            : node;
        if (!targetNode)
            continue;
        // Handle imports
        if (node.type === "import_statement") {
            const imp = extractImport(node);
            if (imp)
                imports.push(imp);
            continue;
        }
        // Handle export { ... } from '...' (re-exports)
        if (isExported && !targetNode) {
            // export { foo } from './bar' — the source is on the export_statement
            const source = node.childForFieldName("source");
            if (source) {
                const imp = extractReexport(node, source);
                if (imp)
                    imports.push(imp);
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
function extractSymbol(node, exported) {
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
function extractFunction(node, exported) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
    const params = node.childForFieldName("parameters");
    const returnType = node.childForFieldName("return_type");
    const typeParams = node.childForFieldName("type_parameters");
    let sig = nameNode.text;
    if (typeParams)
        sig += typeParams.text;
    if (params)
        sig += params.text;
    if (returnType)
        sig += ": " + returnType.text.replace(/^:\s*/, "");
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
function extractClass(node, exported) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
    const children = [];
    const body = node.childForFieldName("body");
    if (body) {
        for (let i = 0; i < body.namedChildCount; i++) {
            const member = body.namedChild(i);
            if (!member)
                continue;
            if (member.type === "method_definition") {
                const method = extractMethod(member);
                if (method)
                    children.push(method);
            }
            else if (member.type === "public_field_definition" ||
                member.type === "property_definition") {
                const prop = extractProperty(member);
                if (prop)
                    children.push(prop);
            }
        }
    }
    const typeParams = node.childForFieldName("type_parameters");
    let sig = nameNode.text;
    if (typeParams)
        sig += typeParams.text;
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
function extractInterface(node, exported) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
    const typeParams = node.childForFieldName("type_parameters");
    let sig = nameNode.text;
    if (typeParams)
        sig += typeParams.text;
    const children = [];
    const body = node.childForFieldName("body");
    if (body) {
        for (let i = 0; i < body.namedChildCount; i++) {
            const member = body.namedChild(i);
            if (!member)
                continue;
            if (member.type === "property_signature" ||
                member.type === "method_signature") {
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
function extractTypeAlias(node, exported) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
    const typeParams = node.childForFieldName("type_parameters");
    const value = node.childForFieldName("value");
    let sig = nameNode.text;
    if (typeParams)
        sig += typeParams.text;
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
function extractEnum(node, exported) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
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
function extractVariable(node, exported) {
    // lexical_declaration contains variable_declarator children
    const declarator = node.namedChildren.find((c) => c.type === "variable_declarator");
    if (!declarator)
        return null;
    const nameNode = declarator.childForFieldName("name");
    if (!nameNode)
        return null;
    const value = declarator.childForFieldName("value");
    const typeAnnotation = declarator.childForFieldName("type");
    // Detect if it's an arrow function
    let kind = "variable";
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
        if (params)
            sig += params.text;
        if (returnType)
            sig += ": " + returnType.text.replace(/^:\s*/, "");
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
function extractMethod(node) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
    const params = node.childForFieldName("parameters");
    const returnType = node.childForFieldName("return_type");
    let sig = nameNode.text;
    if (params)
        sig += params.text;
    if (returnType)
        sig += ": " + returnType.text.replace(/^:\s*/, "");
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
function extractProperty(node) {
    const nameNode = node.childForFieldName("name");
    if (!nameNode)
        return null;
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
function extractImport(node) {
    const sourceNode = node.childForFieldName("source");
    if (!sourceNode)
        return null;
    const source = sourceNode.text.replace(/^['"]|['"]$/g, "");
    const symbols = [];
    // Walk import clause to find named imports
    for (let i = 0; i < node.namedChildCount; i++) {
        const child = node.namedChild(i);
        if (!child)
            continue;
        if (child.type === "import_clause") {
            for (let j = 0; j < child.namedChildCount; j++) {
                const importChild = child.namedChild(j);
                if (!importChild)
                    continue;
                if (importChild.type === "identifier") {
                    // Default import
                    symbols.push(importChild.text);
                }
                else if (importChild.type === "named_imports") {
                    // { foo, bar as baz }
                    for (let k = 0; k < importChild.namedChildCount; k++) {
                        const specifier = importChild.namedChild(k);
                        if (specifier?.type === "import_specifier") {
                            const name = specifier.childForFieldName("name");
                            if (name)
                                symbols.push(name.text);
                        }
                    }
                }
                else if (importChild.type === "namespace_import") {
                    // * as ns
                    const name = importChild.childForFieldName("name");
                    if (name)
                        symbols.push("* as " + name.text);
                }
            }
        }
    }
    return { source, symbols };
}
function extractReexport(node, sourceNode) {
    const source = sourceNode.text.replace(/^['"]|['"]$/g, "");
    const symbols = [];
    // export { foo, bar } from './baz'
    for (let i = 0; i < node.namedChildCount; i++) {
        const child = node.namedChild(i);
        if (child?.type === "export_clause") {
            for (let j = 0; j < child.namedChildCount; j++) {
                const specifier = child.namedChild(j);
                if (specifier?.type === "export_specifier") {
                    const name = specifier.childForFieldName("name");
                    if (name)
                        symbols.push(name.text);
                }
            }
        }
    }
    return { source, symbols };
}
// ── Python parsing ──────────────────────────────────────────────────
function parsePythonFile(root) {
    const symbols = [];
    const imports = [];
    for (let i = 0; i < root.childCount; i++) {
        const node = root.child(i);
        if (!node)
            continue;
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
                const inner = node.namedChildren.find((c) => c.type === "function_definition" || c.type === "class_definition");
                if (inner?.type === "function_definition") {
                    symbols.push(extractPythonFunction(inner));
                }
                else if (inner?.type === "class_definition") {
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
function extractPythonFunction(node) {
    const nameNode = node.childForFieldName("name");
    const params = node.childForFieldName("parameters");
    const returnType = node.childForFieldName("return_type");
    let sig = nameNode.text;
    if (params)
        sig += params.text;
    if (returnType)
        sig += " -> " + returnType.text;
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
function extractPythonClass(node) {
    const nameNode = node.childForFieldName("name");
    const children = [];
    const body = node.childForFieldName("body");
    if (body) {
        for (let i = 0; i < body.namedChildCount; i++) {
            const member = body.namedChild(i);
            if (!member)
                continue;
            if (member.type === "function_definition") {
                const methodName = member.childForFieldName("name");
                if (methodName) {
                    const mParams = member.childForFieldName("parameters");
                    const mReturn = member.childForFieldName("return_type");
                    let mSig = methodName.text;
                    if (mParams)
                        mSig += mParams.text;
                    if (mReturn)
                        mSig += " -> " + mReturn.text;
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
            }
            else if (member.type === "decorated_definition") {
                const inner = member.namedChildren.find((c) => c.type === "function_definition");
                if (inner) {
                    const methodName = inner.childForFieldName("name");
                    if (methodName) {
                        const mParams = inner.childForFieldName("parameters");
                        const mReturn = inner.childForFieldName("return_type");
                        let mSig = methodName.text;
                        if (mParams)
                            mSig += mParams.text;
                        if (mReturn)
                            mSig += " -> " + mReturn.text;
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
    if (superclasses)
        sig += superclasses.text;
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
function extractPythonImport(node) {
    const symbols = [];
    for (let i = 0; i < node.namedChildCount; i++) {
        const child = node.namedChild(i);
        if (child?.type === "dotted_name") {
            symbols.push(child.text);
        }
        else if (child?.type === "aliased_import") {
            const name = child.childForFieldName("name");
            if (name)
                symbols.push(name.text);
        }
    }
    return { source: symbols[0] ?? "", symbols };
}
function extractPythonFromImport(node) {
    const moduleNode = node.childForFieldName("module_name");
    const source = moduleNode?.text ?? "";
    const symbols = [];
    for (let i = 0; i < node.namedChildCount; i++) {
        const child = node.namedChild(i);
        if (child === moduleNode)
            continue;
        if (child?.type === "aliased_import") {
            const name = child.childForFieldName("name");
            if (name)
                symbols.push(name.text);
        }
        else if (child?.type === "dotted_name") {
            symbols.push(child.text);
        }
    }
    if (symbols.length === 0) {
        const match = node.text.match(/import\s+(.+)$/);
        if (match) {
            for (const name of match[1].split(",")) {
                const trimmed = name.trim().split(/\s+as\s+/)[0].trim();
                if (trimmed && trimmed !== "*")
                    symbols.push(trimmed);
            }
        }
    }
    return { source, symbols };
}
//# sourceMappingURL=parser.js.map