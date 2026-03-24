export interface SymbolRow {
    name: string;
    kind: string;
    line: number;
    end_line: number | null;
    signature: string | null;
    exported: number;
    path: string;
    parent_name: string | null;
}
export interface ImportRow {
    path: string;
    symbols: string | null;
}
export interface FileSymbolRow {
    name: string;
    kind: string;
    line: number;
    end_line: number | null;
    signature: string | null;
    exported: number;
    parent_name: string | null;
}
export interface RelatedRow {
    path: string;
    source: string;
    symbols: string | null;
    direction: string;
}
export declare function escapeLike(input: string): string;
export declare function handleNavigate(args: {
    query: string;
}): string;
export declare function handleProjectMap(): string;
export declare function handleFindSymbol(args: {
    name: string;
    kind?: string;
}): string;
export declare function handleFindUsages(args: {
    name: string;
}): string;
export declare function handleFileOverview(args: {
    path: string;
}): string;
export declare function handleRelatedFiles(args: {
    path: string;
}): string;
export declare function handleDeadCode(): string;
export declare function handleChangeImpact(args: {
    symbol: string;
}): string;
export declare function handleContextBudget(): string;
export declare function handleApiSurface(): string;
export declare function handleCircularDeps(): string;
export declare function handleDoctor(): string;
//# sourceMappingURL=handlers.d.ts.map