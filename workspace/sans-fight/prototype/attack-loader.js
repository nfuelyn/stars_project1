/* ============================================================================
 * 攻击脚本加载器：直接读 CSV（与原版 Files/sans_*.csv 同格式）
 * 每行 = 延时, 命令, 参数…；`:Name` 为标签；`$Var` 取值。
 * 之所以保持 CSV 而不是改写成 JS 数组：一来**与原版可逐行对照**，二来循环/跳转
 * 的行号语义（JMPABS 用 1-based 行号）必须和原文件一致才不会错位。
 * ========================================================================== */
(function (global) {
  'use strict';

  function parseCSV(text) {
    var rows = [];
    var lines = String(text).replace(/\r/g, '').split('\n');
    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i];
      if (!ln.trim()) continue;
      if (ln.charAt(0) === '#') continue;          // 注释行（用于标注出处与说明）
      var cells = ln.split(',');
      /* 去掉尾部空单元格 */
      while (cells.length && cells[cells.length - 1] === '') cells.pop();
      rows.push(cells.map(function (c) { return c.trim(); }));
    }
    return rows;
  }

  var api = { parseCSV: parseCSV };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.BTSLoad = api;
})(typeof window !== 'undefined' ? window : globalThis);
