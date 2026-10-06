#!/usr/bin/env node
/**
 * glm-mcp — 零依赖 MCP (stdio) 服务器
 *
 * 底层调用智谱开放平台 OpenAI 兼容接口，默认模型 glm-4.6v-flash（视觉多模态）。
 * 仅使用 Node.js 内置模块（fetch / fs / path），无需 npm install。
 *
 * 限流处理：429 / 1305 等容量错误自动指数退避重试，仍失败则按顺序回退到备用模型。
 *
 * 用法:
 *   node index.js            启动 MCP stdio 服务（供 Codex 调用）
 *   node index.js --check    检查主模型（含重试/回退）是否可用
 *   node index.js --probe    逐个探测主模型与备用模型，打印状态表
 *   node index.js --ask "你好"   命令行快速提问
 *   node index.js --list-tools   打印工具定义
 */
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER_NAME = 'glm-mcp';
const SERVER_VERSION = '1.1.0';
const PROTOCOL_FALLBACK = '2025-06-18';
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const MIME_BY_EXT = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

// HTTP 状态码 / 智谱错误码 → 值得重试或换模型
const RETRYABLE_STATUS = new Set([408, 429, 500, 502, 503, 504]);
const RETRYABLE_CODES = new Set(['1113', '1301', '1302', '1304', '1305']);
const MODEL_MISSING_CODES = new Set(['1210', '1211']);
const RETRY_BASE_MS = 2000;
const RETRY_MAX_MS = 20000;

/* ------------------------------------------------------------------ */
/* 配置                                                                */
/* ------------------------------------------------------------------ */

function loadDotEnv() {
  const envPath = resolve(__dirname, '.env');
  if (!existsSync(envPath)) return;
  let raw = '';
  try {
    raw = readFileSync(envPath, 'utf8');
  } catch {
    return;
  }
  for (const line of raw.split(/\r?\n/)) {
    const matched = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/.exec(line);
    if (!matched) continue;
    const key = matched[1];
    if (process.env[key] !== undefined) continue;
    let value = matched[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"') && value.length > 1) ||
      (value.startsWith("'") && value.endsWith("'") && value.length > 1)
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

loadDotEnv();

const splitList = (value) =>
  String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);

function readConfig() {
  const apiKey =
    process.env.GLM_API_KEY ||
    process.env.ZHIPUAI_API_KEY ||
    process.env.ZHIPU_API_KEY ||
    process.env.BIGMODEL_API_KEY ||
    '';
  const baseUrl = (process.env.GLM_BASE_URL || 'https://open.bigmodel.cn/api/paas/v4').replace(/\/+$/, '');
  return {
    apiKey,
    endpoint: process.env.GLM_API_URL || `${baseUrl}/chat/completions`,
    model: process.env.GLM_MODEL || 'glm-4.6v-flash',
    textFallbacks: splitList(process.env.GLM_FALLBACK_MODELS ?? 'glm-4.5-flash,glm-4-flash'),
    visionFallbacks: splitList(process.env.GLM_VISION_FALLBACK_MODELS ?? 'glm-4v-flash'),
    timeoutMs: Number(process.env.GLM_TIMEOUT_MS || 180000),
    maxTokens: Number(process.env.GLM_MAX_TOKENS || 4096),
    retries: Number.isFinite(Number(process.env.GLM_RETRIES)) ? Math.max(0, Number(process.env.GLM_RETRIES)) : 2,
  };
}

/* ------------------------------------------------------------------ */
/* 错误类型                                                            */
/* ------------------------------------------------------------------ */

class GlmError extends Error {
  constructor(message, { retryable = false, modelUnavailable = false, status = 0, code = '' } = {}) {
    super(message);
    this.name = 'GlmError';
    this.retryable = retryable;
    this.modelUnavailable = modelUnavailable;
    this.status = status;
    this.code = code;
  }
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const truncate = (value, limit) => {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  if (!text) return '';
  return text.length > limit ? `${text.slice(0, limit)}…` : text;
};

function parseErrorBody(raw) {
  try {
    const data = JSON.parse(raw);
    return { code: String(data?.error?.code ?? ''), message: data?.error?.message ?? '' };
  } catch {
    return { code: '', message: '' };
  }
}

/* ------------------------------------------------------------------ */
/* GLM API                                                             */
/* ------------------------------------------------------------------ */

function resolveImage(source, cwd) {
  if (/^(https?:\/\/|data:)/i.test(source)) return source;
  const root = process.env.GLM_IMAGE_ROOT || cwd || process.cwd();
  const filePath = isAbsolute(source) ? source : resolve(root, source);
  if (!existsSync(filePath)) {
    throw new Error(`找不到图片文件: ${filePath}`);
  }
  const info = statSync(filePath);
  if (!info.isFile()) {
    throw new Error(`不是文件: ${filePath}`);
  }
  if (info.size > MAX_IMAGE_BYTES) {
    throw new Error(`图片过大 (${(info.size / 1024 / 1024).toFixed(1)}MB)，上限 20MB: ${filePath}`);
  }
  const mime = MIME_BY_EXT[extname(filePath).toLowerCase()];
  if (!mime) {
    throw new Error(`不支持的图片格式 ${extname(filePath) || '(无扩展名)'}，支持 png/jpg/jpeg/webp/gif: ${filePath}`);
  }
  return `data:${mime};base64,${readFileSync(filePath).toString('base64')}`;
}

function buildUserContent(prompt, images, cwd) {
  const imageList = Array.isArray(images) ? images.filter((item) => typeof item === 'string' && item.trim()) : [];
  if (imageList.length === 0) return prompt;
  const parts = [{ type: 'text', text: prompt }];
  for (const image of imageList) {
    parts.push({ type: 'image_url', image_url: { url: resolveImage(image.trim(), cwd) } });
  }
  return parts;
}

function extractText(message) {
  if (!message) return '';
  const content = message.content;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part && typeof part.text === 'string') return part.text;
        return '';
      })
      .join('');
  }
  if (content && typeof content === 'object' && typeof content.text === 'string') {
    return content.text;
  }
  return '';
}

function buildBody(model, messages, options, config) {
  const body = { model, messages, stream: false };
  const temperature = Number(options.temperature);
  if (Number.isFinite(temperature)) body.temperature = temperature;
  const maxTokens = Number(options.max_tokens);
  body.max_tokens = Number.isFinite(maxTokens) && maxTokens > 0 ? maxTokens : config.maxTokens;
  if (typeof options.thinking === 'boolean') {
    body.thinking = { type: options.thinking ? 'enabled' : 'disabled' };
  }
  return body;
}

async function requestModel(config, model, messages, options) {
  const body = buildBody(model, messages, options, config);
  const retries = Number.isFinite(Number(options.retries)) ? Math.max(0, Number(options.retries)) : config.retries;
  let lastError = null;

  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.timeoutMs);
    try {
      const response = await fetch(config.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${config.apiKey}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const raw = await response.text();
      clearTimeout(timer);

      if (!response.ok) {
        const info = parseErrorBody(raw);
        const modelUnavailable = MODEL_MISSING_CODES.has(info.code);
        const retryable = !modelUnavailable && (RETRYABLE_STATUS.has(response.status) || RETRYABLE_CODES.has(info.code));
        const detail = info.message ? `: ${info.message}` : `: ${truncate(raw, 400)}`;
        const error = new GlmError(
          `GLM API (${model}) 返回 ${response.status}${info.code ? ` [${info.code}]` : ''}${detail}`,
          { retryable, modelUnavailable, status: response.status, code: info.code }
        );
        lastError = error;
        if (retryable && attempt < retries) {
          const wait = Math.min(RETRY_BASE_MS * 2 ** attempt, RETRY_MAX_MS) + Math.floor(Math.random() * 400);
          console.error(`[glm-mcp] ${model} 繁忙(${info.code || response.status})，${wait}ms 后重试 (${attempt + 1}/${retries})`);
          await sleep(wait);
          continue;
        }
        throw error;
      }

      let data;
      try {
        data = JSON.parse(raw);
      } catch {
        throw new GlmError(`GLM API (${model}) 返回了非 JSON 内容: ${truncate(raw, 400)}`);
      }
      const choice = data?.choices?.[0];
      if (!choice) {
        throw new GlmError(`GLM API (${model}) 响应中没有 choices 字段: ${truncate(raw, 800)}`);
      }
      const message = choice.message || {};
      const text = extractText(message) || (typeof choice.text === 'string' ? choice.text : '');
      const reasoning = typeof message.reasoning_content === 'string' ? message.reasoning_content : '';
      return {
        text: text || (reasoning ? '' : '(模型返回了空内容)'),
        reasoning,
        finishReason: choice.finish_reason || '',
        model: data.model || model,
        usage: data.usage || null,
        requestId: data.request_id || data.id || null,
      };
    } catch (error) {
      clearTimeout(timer);
      const aborted = error?.name === 'AbortError';
      const wrapped = aborted
        ? new GlmError(`GLM API (${model}) 请求超时（${config.timeoutMs}ms）`, { retryable: true })
        : error instanceof GlmError
          ? error
          : new GlmError(`无法连接 GLM API (${config.endpoint}): ${error?.cause?.code || error?.message || String(error)}`, { retryable: true });
      lastError = wrapped;
      if (wrapped.retryable && attempt < retries) {
        const wait = Math.min(RETRY_BASE_MS * 2 ** attempt, RETRY_MAX_MS) + Math.floor(Math.random() * 400);
        console.error(`[glm-mcp] ${model} 请求失败，${wait}ms 后重试 (${attempt + 1}/${retries})：${wrapped.message}`);
        await sleep(wait);
        continue;
      }
      throw wrapped;
    }
  }
  throw lastError || new GlmError('GLM API 调用失败');
}

function modelChain(config, requestedModel, hasImages, override) {
  const primary = requestedModel || config.model;
  const fallbacks = Array.isArray(override) ? override : hasImages ? config.visionFallbacks : config.textFallbacks;
  return [primary, ...fallbacks].filter((model, index, list) => model && list.indexOf(model) === index);
}

async function callGlm(options) {
  const config = readConfig();
  if (!config.apiKey) {
    throw new GlmError(
      '未找到 API Key。请在 D:\\stars\\glm-mcp\\.env 中设置 GLM_API_KEY=你的智谱Key（可在 https://open.bigmodel.cn 获取）。'
    );
  }

  const cwd = options.cwd || process.cwd();
  const userContent = buildUserContent(String(options.prompt ?? ''), options.images, cwd);
  const hasImages = Array.isArray(userContent);
  const messages = [];
  if (options.system && String(options.system).trim()) {
    messages.push({ role: 'system', content: String(options.system) });
  }
  messages.push({ role: 'user', content: userContent });

  const chain = modelChain(config, options.model, hasImages, options.fallbacks);
  let lastError = null;
  for (let index = 0; index < chain.length; index += 1) {
    const model = chain[index];
    try {
      const result = await requestModel(config, model, messages, options);
      return { ...result, fallbackFrom: index === 0 ? '' : chain[0] };
    } catch (error) {
      lastError = error;
      const canFallback = error instanceof GlmError && (error.retryable || error.modelUnavailable);
      if (!canFallback) throw error;
      if (index < chain.length - 1) {
        console.error(`[glm-mcp] ${model} 不可用，回退到 ${chain[index + 1]}：${error.message}`);
      }
    }
  }
  throw lastError || new GlmError('所有模型均调用失败');
}

function formatResult(result, { includeMeta = false, includeReasoning = false } = {}) {
  const blocks = [];
  if (includeReasoning && result.reasoning) blocks.push(`[思考过程]\n${result.reasoning}`);
  blocks.push(result.text || '(模型返回了空内容)');
  if (result.fallbackFrom) {
    blocks.push(`(注：${result.fallbackFrom} 当前繁忙或不可用，已自动回退到 ${result.model}。)`);
  }
  if (includeMeta) {
    const usage = result.usage
      ? `tokens: prompt=${result.usage.prompt_tokens ?? '?'}, completion=${result.usage.completion_tokens ?? '?'}, total=${result.usage.total_tokens ?? '?'}`
      : 'tokens: 未知';
    blocks.push(`---\nmodel: ${result.model} | finish: ${result.finishReason || 'n/a'} | ${usage}${result.requestId ? ` | request_id: ${result.requestId}` : ''}`);
  }
  return blocks.join('\n\n');
}

/* ------------------------------------------------------------------ */
/* MCP 工具定义                                                        */
/* ------------------------------------------------------------------ */

const MODEL_PROP = {
  type: 'string',
  description: '模型名，默认 glm-4.6v-flash，也可传 glm-4.5、glm-4.6 等智谱模型。',
};
const SYSTEM_PROP = { type: 'string', description: '系统提示词（可选）。' };
const TEMPERATURE_PROP = { type: 'number', description: '采样温度 0~1（可选）。' };
const MAX_TOKENS_PROP = { type: 'integer', description: '最大输出 token 数（可选）。' };
const THINKING_PROP = { type: 'boolean', description: '是否开启深度思考（仅模型支持时有效，可选）。' };
const META_PROP = { type: 'boolean', description: '是否在结果末尾附上模型名/token 用量等元信息，默认 false。' };
const REASONING_PROP = { type: 'boolean', description: '是否显示模型返回的思考过程（reasoning_content），默认 false。' };

const TOOLS = [
  {
    name: 'glm_chat',
    title: 'GLM 文本对话',
    description:
      '调用智谱 GLM 模型（默认 glm-4.6v-flash）进行纯文本问答、写作、代码总结、翻译等。遇到限流会自动重试并回退备用模型。',
    annotations: { title: 'GLM 文本对话', readOnlyHint: true, destructiveHint: false, openWorldHint: true },
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string', description: '要发送给模型的提示词。' },
        system: SYSTEM_PROP,
        model: MODEL_PROP,
        temperature: TEMPERATURE_PROP,
        max_tokens: MAX_TOKENS_PROP,
        thinking: THINKING_PROP,
        include_meta: META_PROP,
        include_reasoning: REASONING_PROP,
      },
      required: ['prompt'],
      additionalProperties: false,
    },
  },
  {
    name: 'glm_vision',
    title: 'GLM 图像理解',
    description:
      '让 glm-4.6v-flash 看图并回答问题。images 可传本地绝对路径、相对路径或 http(s)/data URL，支持 png/jpg/jpeg/webp/gif，单图上限 20MB。',
    annotations: { title: 'GLM 图像理解', readOnlyHint: true, destructiveHint: false, openWorldHint: true },
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string', description: '针对图片提出的问题或要求。' },
        images: {
          type: 'array',
          items: { type: 'string' },
          minItems: 1,
          description: '一张或多张图片：本地路径（如 D:\\pics\\a.png）或 http(s)/data URL。',
        },
        system: SYSTEM_PROP,
        model: MODEL_PROP,
        temperature: TEMPERATURE_PROP,
        max_tokens: MAX_TOKENS_PROP,
        thinking: THINKING_PROP,
        include_meta: META_PROP,
        include_reasoning: REASONING_PROP,
      },
      required: ['prompt', 'images'],
      additionalProperties: false,
    },
  },
];

async function runTool(name, args) {
  const cwd = process.env.GLM_IMAGE_ROOT || process.cwd();
  const common = {
    system: args?.system,
    model: args?.model,
    temperature: args?.temperature,
    max_tokens: args?.max_tokens,
    thinking: args?.thinking,
    cwd,
  };

  if (name === 'glm_chat') {
    if (!args || typeof args.prompt !== 'string' || !args.prompt.trim()) {
      throw new Error('参数 prompt 必填且不能为空');
    }
    const result = await callGlm({ ...common, prompt: args.prompt });
    return formatResult(result, { includeMeta: args.include_meta === true, includeReasoning: args.include_reasoning === true });
  }

  if (name === 'glm_vision') {
    if (!args || typeof args.prompt !== 'string' || !args.prompt.trim()) {
      throw new Error('参数 prompt 必填且不能为空');
    }
    if (!Array.isArray(args.images) || args.images.length === 0) {
      throw new Error('参数 images 必填，至少提供一张图片');
    }
    const result = await callGlm({ ...common, prompt: args.prompt, images: args.images });
    return formatResult(result, { includeMeta: args.include_meta === true, includeReasoning: args.include_reasoning === true });
  }

  throw new Error(`未知工具: ${name}`);
}

/* ------------------------------------------------------------------ */
/* JSON-RPC over stdio                                                 */
/* ------------------------------------------------------------------ */

function send(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function sendResult(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function sendError(id, code, message, data) {
  send({ jsonrpc: '2.0', id, error: { code, message, ...(data ? { data } : {}) } });
}

async function handleMessage(message) {
  const { id, method, params } = message;
  const isRequest = Object.prototype.hasOwnProperty.call(message, 'id');

  if (method === 'initialize') {
    sendResult(id, {
      protocolVersion: params?.protocolVersion || PROTOCOL_FALLBACK,
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      instructions:
        'GLM MCP：glm_chat 用于纯文本问答，glm_vision 用于图像理解（可传本地图片路径）。默认模型 glm-4.6v-flash，遇限流自动重试并回退备用模型。',
    });
    return;
  }

  if (
    method === 'notifications/initialized' ||
    method === 'notifications/cancelled' ||
    method === 'notifications/roots/list_changed'
  ) {
    return;
  }

  if (method === 'ping') {
    sendResult(id, {});
    return;
  }

  if (method === 'tools/list') {
    sendResult(id, { tools: TOOLS });
    return;
  }

  if (method === 'tools/call') {
    const toolName = params?.name;
    const args = params?.arguments || {};
    try {
      const text = await runTool(toolName, args);
      sendResult(id, { content: [{ type: 'text', text }], isError: false });
    } catch (error) {
      sendResult(id, {
        content: [{ type: 'text', text: `调用 ${toolName} 失败: ${error?.message || String(error)}` }],
        isError: true,
      });
    }
    return;
  }

  if (method === 'resources/list') {
    sendResult(id, { resources: [] });
    return;
  }

  if (method === 'prompts/list') {
    sendResult(id, { prompts: [] });
    return;
  }

  if (method === 'logging/setLevel') {
    sendResult(id, {});
    return;
  }

  if (!isRequest) return;
  sendError(id, -32601, `Method not found: ${method}`);
}

function startStdioServer() {
  let buffer = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    buffer += chunk;
    let index = buffer.indexOf('\n');
    while (index >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (line) {
        let message = null;
        try {
          message = JSON.parse(line);
        } catch {
          sendError(null, -32700, 'Parse error: 收到非 JSON 行');
        }
        if (message) {
          handleMessage(message).catch((error) => {
            if (Object.prototype.hasOwnProperty.call(message, 'id')) {
              sendError(message.id, -32603, error?.message || String(error));
            }
          });
        }
      }
      index = buffer.indexOf('\n');
    }
  });
  process.stdin.on('end', () => process.exit(0));
}

/* ------------------------------------------------------------------ */
/* 命令行辅助                                                          */
/* ------------------------------------------------------------------ */

const [, , command, ...rest] = process.argv;
const modelArg = rest.find((item) => item.startsWith('--model='))?.slice('--model='.length);
const promptArgs = rest.filter((item) => !item.startsWith('--'));

if (command === '--check') {
  const config = readConfig();
  const maskedKey = config.apiKey ? `${config.apiKey.slice(0, 6)}…${config.apiKey.slice(-4)}` : '(未设置)';
  console.log(`[glm-mcp] endpoint: ${config.endpoint}`);
  console.log(`[glm-mcp] model:    ${config.model}  (备用: ${config.textFallbacks.join(', ') || '无'})`);
  console.log(`[glm-mcp] api key:  ${maskedKey}`);
  try {
    const result = await callGlm({ prompt: '只回复两个字：可用', max_tokens: 64, model: modelArg });
    console.log(`[glm-mcp] 调用成功: ${(result.text || '').trim() || '(空)'}${result.fallbackFrom ? `（回退自 ${result.fallbackFrom}，实际模型 ${result.model}）` : ''}`);
    process.exit(0);
  } catch (error) {
    console.error(`[glm-mcp] 调用失败: ${error?.message || String(error)}`);
    process.exit(1);
  }
} else if (command === '--probe') {
  const config = readConfig();
  const models = [modelArg || config.model, ...config.textFallbacks, ...config.visionFallbacks].filter(
    (model, index, list) => model && list.indexOf(model) === index
  );
  console.log(`[glm-mcp] 逐个探测: ${models.join(', ')}`);
  for (const model of models) {
    try {
      const result = await callGlm({ prompt: 'ping', max_tokens: 32, model, retries: 0, fallbacks: [] });
      console.log(`  ${model.padEnd(24)} OK   ${(result.text || '').replace(/\s+/g, ' ').slice(0, 40)}`);
    } catch (error) {
      console.log(`  ${model.padEnd(24)} FAIL ${error?.message || String(error)}`);
    }
  }
  process.exit(0);
} else if (command === '--ask') {
  const prompt = promptArgs.join(' ').trim();
  if (!prompt) {
    console.error('用法: node index.js --ask "你的问题" [--model=glm-4.5-flash]');
    process.exit(2);
  }
  try {
    const result = await callGlm({ prompt, model: modelArg });
    console.log(formatResult(result, { includeMeta: true, includeReasoning: true }));
    process.exit(0);
  } catch (error) {
    console.error(`调用失败: ${error?.message || String(error)}`);
    process.exit(1);
  }
} else if (command === '--list-tools') {
  console.log(JSON.stringify(TOOLS, null, 2));
  process.exit(0);
} else if (command === '--version') {
  console.log(`${SERVER_NAME} ${SERVER_VERSION}`);
  process.exit(0);
} else if (command === '--image') {
  const images = [];
  let prompt = '请详细描述这张图片的内容。';
  for (let i = 0; i < rest.length; i += 1) {
    const item = rest[i];
    if (item.startsWith('--prompt=')) prompt = item.slice('--prompt='.length);
    else if (item === '--prompt' && rest[i + 1]) { prompt = rest[i + 1]; i += 1; }
    else if (item.startsWith('--')) continue;
    else images.push(item);
  }
  if (images.length === 0) {
    console.error('用法: node index.js --image "D:\\pics\\a.png" [--prompt "问题"] [--model=glm-4.6v-flash]');
    process.exit(2);
  }
  try {
    const result = await callGlm({ prompt, images, model: modelArg });
    console.log(formatResult(result, { includeMeta: true }));
    process.exit(0);
  } catch (error) {
    console.error(`调用失败: ${error?.message || String(error)}`);
    process.exit(1);
  }} else if (command === '--help') {
  console.log(
    'glm-mcp — 智谱 GLM MCP 服务器\n\n  node index.js            启动 MCP stdio 服务\n  node index.js --check    检查主模型（含重试/回退）\n  node index.js --probe    逐个探测主模型与备用模型\n  node index.js --ask "…"  命令行提问\n  node index.js --image "图片路径" [--prompt "…"]  命令行识图\n  node index.js --list-tools\n'
  );
  process.exit(0);
} else {
  startStdioServer();
}







