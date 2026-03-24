export interface IndexStats {
    totalFiles: number;
    indexedFiles: number;
    skippedFiles: number;
    removedFiles: number;
    totalSymbols: number;
    totalImports: number;
    durationMs: number;
}
export interface SingleFileStats {
    symbols: number;
    imports: number;
    durationMs: number;
    deleted: boolean;
}
export declare function indexSingleFile(projectRoot: string, relPath: string): Promise<SingleFileStats>;
export declare function indexProject(projectRoot: string): Promise<IndexStats>;
//# sourceMappingURL=indexer.d.ts.map