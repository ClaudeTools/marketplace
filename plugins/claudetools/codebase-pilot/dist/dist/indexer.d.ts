export interface IndexStats {
    totalFiles: number;
    indexedFiles: number;
    skippedFiles: number;
    removedFiles: number;
    totalSymbols: number;
    totalImports: number;
    durationMs: number;
}
export declare function indexProject(projectRoot: string): IndexStats;
//# sourceMappingURL=indexer.d.ts.map