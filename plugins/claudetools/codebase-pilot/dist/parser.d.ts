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
export type SymbolKind = "function" | "class" | "interface" | "type" | "enum" | "variable" | "method" | "property";
export type SupportedLanguage = "typescript" | "tsx" | "javascript" | "jsx" | "python" | "go" | "rust" | "java" | "kotlin" | "ruby" | "c_sharp" | "php" | "swift" | "c" | "cpp" | "bash";
export declare function detectLanguage(filePath: string): SupportedLanguage | null;
export declare function parseFile(source: string, language: SupportedLanguage): Promise<ParseResult>;
//# sourceMappingURL=parser.d.ts.map