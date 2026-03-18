import Database from "better-sqlite3";
export declare function getDbPath(projectRoot: string): string;
export declare function openDatabase(projectRoot: string): Database.Database;
export interface DbStatements {
    insertFile: Database.Statement;
    updateFile: Database.Statement;
    getFile: Database.Statement;
    deleteFile: Database.Statement;
    deleteSymbolsByFile: Database.Statement;
    deleteImportsByFile: Database.Statement;
    insertSymbol: Database.Statement;
    insertImport: Database.Statement;
    getAllFiles: Database.Statement;
}
export declare function prepareStatements(db: Database.Database): DbStatements;
//# sourceMappingURL=db.d.ts.map