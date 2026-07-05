import express from 'express';
import cors from 'cors';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import nodemailer from 'nodemailer';
import pkg from 'pg';
import multer from 'multer';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import sharp from 'sharp';
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import fetch from 'node-fetch';
import dotenv from 'dotenv';
import axios from 'axios';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import { body, validationResult } from 'express-validator';
import csrf from 'csurf';
import cookieParser from 'cookie-parser';
import { WebSocketServer } from 'ws';
import http from 'http';

dotenv.config();
console.log('📄 Загружен JWT_SECRET из .env:', process.env.JWT_SECRET ? '✅ найден' : '❌ НЕ НАЙДЕН');
console.log('📄 JWT_SECRET (первые 5 символов):', process.env.JWT_SECRET ? process.env.JWT_SECRET.substring(0,5) + '...' : 'null');

const { Pool } = pkg;

// ==================== НАСТРОЙКА ПУТЕЙ ====================
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 🔐 УСИЛЕННАЯ БЕЗОПАСНОСТЬ: Все секреты должны быть в .env файле!
const ENCRYPTION_KEY = Buffer.from(
  process.env.ENCRYPTION_KEY || crypto.randomBytes(32).toString('hex'), 
  'hex'
);

// ⚠️ ВНИМАНИЕ: для продакшена используйте process.env.JWT_SECRET
const JWT_SECRET = process.env.JWT_SECRET || 'P|K)3nY1-{gv3EMGx7:X8TD&[wrGHP.R';
const EMAIL_USER = process.env.EMAIL_USER || 'david.berngardt@gmail.com';
const EMAIL_PASS = process.env.EMAIL_PASS || 'trrb fhnv qrja yspy';
const PORT = process.env.PORT || 3004;
const BASE_URL = process.env.BASE_URL || `http://localhost:${PORT}`;

// Пути для Flutter Web
const WEB_DIR = path.join(__dirname, 'web');
const ASSETS_DIR = path.join(WEB_DIR, 'assets');

console.log('=== СЕРВЕР ЗАПУСК (Локальная разработка) ===');
console.log('📁 Web директория:', WEB_DIR);
console.log('🌐 Порт:', PORT);
console.log('🌐 BASE_URL:', BASE_URL);

// ==================== 🔐 ФУНКЦИЯ НОРМАЛИЗАЦИИ EMAIL ДЛЯ MAP ====================
function getMapKey(email) {
    if (!email) return email;
    return email.toLowerCase().trim();
}

// ==================== КОНФИГУРАЦИЯ JANUS ====================
const JANUS_ADMIN_URL = process.env.JANUS_ADMIN_URL || 'http://localhost:8088';
const JANUS_WS_URL = process.env.JANUS_WS_URL || 'ws://localhost:8188';
const JANUS_API_SECRET = process.env.JANUS_API_SECRET || 'janusrocks';

// ==================== HELPER ФУНКЦИИ ДЛЯ ЗВОНКОВ ====================

// Генерация ID транзакции для Janus
function generateTransactionId() {
  return Math.random().toString(36).substring(2, 15) + 
         Math.random().toString(36).substring(2, 15);
}

// Генерация токена для Janus
function generateJanusToken(userId, roomId) {
  const payload = {
    userId: userId,
    roomId: roomId,
    timestamp: Date.now(),
    exp: Date.now() + 3600000 // 1 час
  };
  return crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}

// Получение ICE серверов
function getIceServers() {
  return [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' },
    { urls: 'stun:stun3.l.google.com:19302' },
    { urls: 'stun:stun4.l.google.com:19302' }
  ];
}

// Проверка подключения к Janus
async function checkJanusConnection() {
  try {
    const response = await axios.get(`${JANUS_ADMIN_URL}/janus`, {
      timeout: 5000
    });
    return response.status === 200;
  } catch (error) {
    console.error('❌ Janus connection check failed:', error.message);
    return false;
  }
}

// Очистка ресурсов Janus
async function cleanupJanusResources(sessionId, handleId, roomId) {
  try {
    if (handleId) {
      await axios.post(`${JANUS_ADMIN_URL}/janus/${sessionId}/${handleId}`, {
        janus: 'destroy',
        transaction: generateTransactionId()
      }, { timeout: 5000 });
    }
    
    await axios.post(`${JANUS_ADMIN_URL}/janus/${sessionId}`, {
      janus: 'destroy',
      transaction: generateTransactionId()
    }, { timeout: 5000 });
    
    if (roomId) {
      try {
        await axios.post(`${JANUS_ADMIN_URL}/janus/${sessionId}/${handleId}`, {
          janus: 'message',
          body: {
            request: 'destroy',
            room: roomId
          },
          transaction: generateTransactionId()
        }, { timeout: 5000 });
      } catch (roomError) {}
    }
    
    console.log('✅ Janus resources cleaned up');
  } catch (error) {
    console.error('⚠️ Janus cleanup error:', error.message);
  }
}

// Вспомогательная функция для форматирования длительности
function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  
  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  } else {
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  }
}

/* ==================== 🔐 MESSAGE CRYPTO ==================== */
function encryptMessage(text) {
  if (!text || typeof text !== 'string') return '';

  if (
    text.startsWith('Файл: ') ||
    text === 'Голосовое сообщение' ||
    text === 'Изображение'
  ) {
    return text;
  }

  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);

  let encrypted = cipher.update(text, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  const tag = cipher.getAuthTag();

  return `${iv.toString('hex')}:${tag.toString('hex')}:${encrypted}`;
}

function decryptMessage(data) {
  if (!data || typeof data !== 'string') return '';

  if (
    data.startsWith('Файл: ') ||
    data === 'Голосовое сообщение' ||
    data === 'Изображение'
  ) {
    return data;
  }

  const parts = data.split(':');
  if (parts.length !== 3) return data;

  try {
    const [ivHex, tagHex, encryptedHex] = parts;

    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      ENCRYPTION_KEY,
      Buffer.from(ivHex, 'hex')
    );
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));

    let decrypted = decipher.update(Buffer.from(encryptedHex, 'hex'), undefined, 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  } catch {
    return '[Сообщение зашифровано другим ключом]';
  }
}

/* ==================== 🔐 EMAIL/NICKNAME/NAME CRYPTO ==================== */
function hashEmail(email) {
  return crypto.createHash('sha256').update(email.toLowerCase()).digest('hex');
}

// Универсальная функция для шифрования любых строк (email, имя, никнейм)
function encryptString(text) {
  if (!text || typeof text !== 'string') return null;
  
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);

  let encrypted = cipher.update(text, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  const tag = cipher.getAuthTag();
  return `${iv.toString('hex')}:${tag.toString('hex')}:${encrypted}`;
}

function decryptString(data) {
  if (!data) return null;
  const parts = data.split(':');
  if (parts.length !== 3) return null;

  try {
    const [ivHex, tagHex, encryptedHex] = parts;
    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      ENCRYPTION_KEY,
      Buffer.from(ivHex, 'hex')
    );
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));

    let decrypted = decipher.update(Buffer.from(encryptedHex, 'hex'), undefined, 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  } catch {
    return null;
  }
}

// Для обратной совместимости
const encryptEmail = encryptString;
const decryptEmail = decryptString;

// ==================== 🔐 ФУНКЦИИ БЕЗОПАСНОСТИ ====================

// 🔐 Функция для санитизации входных данных
function sanitizeInput(input) {
  if (typeof input !== 'string') return input;
  return input.replace(/[\x00-\x1F\x7F]/g, '').trim();
}

// 🔐 Валидация email
function isValidEmail(email) {
  const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  return emailRegex.test(email);
}

// 🔐 Усиленная валидация пароля
function validatePasswordStrength(password) {
  const errors = [];
  
  if (password.length < 10) {
    errors.push('Минимум 10 символов');
  }
  
  if (!/[A-Z]/.test(password)) {
    errors.push('Хотя бы одна заглавная буква');
  }
  
  if (!/[a-z]/.test(password)) {
    errors.push('Хотя бы одна строчная буква');
  }
  
  if (!/\d/.test(password)) {
    errors.push('Хотя бы одна цифра');
  }
  
  if (!/[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]/.test(password)) {
    errors.push('Хотя бы один специальный символ');
  }
  
  const commonPasswords = ['password123', 'qwerty123', 'admin123', '1234567890'];
  if (commonPasswords.includes(password.toLowerCase())) {
    errors.push('Слишком простой пароль');
  }
  
  if (/(012|123|234|345|456|567|678|789|890)/.test(password)) {
    errors.push('Пароль содержит последовательность цифр');
  }
  
  if (/(.)\1{3,}/.test(password)) {
    errors.push('Пароль содержит повторяющиеся символы');
  }
  
  return {
    isValid: errors.length === 0,
    errors
  };
}

// 7. Генерация кода подтверждения
function generateVerificationCode() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}

// 8. Тестовая функция для проверки шифрования
function testEncryption() {
    console.log('\n🔐 ТЕСТ ШИФРОВАНИЯ:');
    
    const testText = 'Тестовое сообщение для проверки шифрования';
    const testEmail = 'test@example.com';
    const testName = 'Иван Петров';
    const testNickname = 'ivan123';
    
    console.log('📝 Тест сообщений:');
    const encryptedText = encryptMessage(testText);
    console.log('   Оригинал:', testText);
    console.log('   Зашифровано:', encryptedText.substring(0, 50) + '...');
    console.log('   Длина зашифрованного:', encryptedText.length);
    
    const decryptedText = decryptMessage(encryptedText);
    console.log('   Расшифровано:', decryptedText);
    console.log('   Совпадает:', testText === decryptedText ? '✅' : '❌');
    
    console.log('\n📧 Тест email:');
    const encryptedEmail = encryptString(testEmail);
    console.log('   Оригинал:', testEmail);
    console.log('   Зашифровано:', encryptedEmail.substring(0, 50) + '...');
    
    const decryptedEmail = decryptString(encryptedEmail);
    console.log('   Расшифровано:', decryptedEmail);
    console.log('   Совпадает:', testEmail === decryptedEmail ? '✅' : '❌');
    
    console.log('\n👤 Тест имени:');
    const encryptedName = encryptString(testName);
    console.log('   Оригинал:', testName);
    console.log('   Зашифровано:', encryptedName.substring(0, 50) + '...');
    
    const decryptedName = decryptString(encryptedName);
    console.log('   Расшифровано:', decryptedName);
    console.log('   Совпадает:', testName === decryptedName ? '✅' : '❌');
    
    console.log('\n🔖 Тест никнейма:');
    const encryptedNickname = encryptString(testNickname);
    console.log('   Оригинал:', testNickname);
    console.log('   Зашифровано:', encryptedNickname.substring(0, 50) + '...');
    
    const decryptedNickname = decryptString(encryptedNickname);
    console.log('   Расшифровано:', decryptedNickname);
    console.log('   Совпадает:', testNickname === decryptedNickname ? '✅' : '❌');
    
    console.log('\n🔗 Тест хэша email:');
    const emailHash = hashEmail(testEmail);
    console.log('   Хэш:', emailHash);
    console.log('   Длина хэша:', emailHash.length);
    console.log('   Постоянный ли хэш:', emailHash === hashEmail('TEST@EXAMPLE.COM') ? '✅' : '❌');
    
    return testText === decryptedText && testEmail === decryptedEmail && 
           testName === decryptedName && testNickname === decryptedNickname;
}

// Автоматически запускаем тест при старте (только для дебага)
if (process.env.NODE_ENV === 'development') {
    console.log('\n🧪 Запуск теста шифрования...');
    const testPassed = testEncryption();
    console.log(testPassed ? '✅ Тест шифрования пройден' : '❌ Тест шифрования не пройден');
}

// ==================== ИНИЦИАЛИЗАЦИЯ ====================
const app = express();

// ==================== 🔐 КОНФИГУРАЦИЯ HELMET (HTTP ЗАГОЛОВКИ) ====================
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
      imgSrc: ["'self'", "data:", "https:", "http://localhost:9000"],
      connectSrc: [
        "'self'", 
        "ws://localhost:8188", 
        "wss://localhost:8188",
        "http://localhost:3004",
        "http://localhost:5000"
      ],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'"],
      frameSrc: ["'none'"],
    },
  },
  crossOriginEmbedderPolicy: false,
  crossOriginResourcePolicy: { policy: "cross-origin" },
}));

// ==================== 🔐 COOKIE PARSER ДЛЯ CSRF ====================
app.use(cookieParser());

// ==================== ЛОГИРОВАНИЕ ЗАПРОСОВ ====================
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
    next();
});

// ==================== 🔐 УЛУЧШЕННЫЙ CORS ====================
const corsOptions = {
  origin: function (origin, callback) {
    const allowedOrigins = [
      'http://localhost:3004',
      'http://localhost:3000',
      'http://127.0.0.1:3000', 
      'http://localhost:5000',
      'http://localhost:8080',
      'http://localhost:3001'
    ];
    
    if (!origin) return callback(null, true);
    
    if (allowedOrigins.indexOf(origin) !== -1 || process.env.NODE_ENV !== 'production') {
      callback(null, true);
    } else {
      callback(new Error('CORS policy violation'));
    }
  },
  credentials: true,
  optionsSuccessStatus: 200
};

app.use(cors(corsOptions));

// ==================== MIDDLEWARE ДЛЯ АВТОМАТИЧЕСКОГО ДОБАВЛЕНИЯ /api ====================
// Этот middleware автоматически добавляет префикс /api к запросам,
// которые ожидают его, но не имеют его в URL
app.use((req, res, next) => {
  // Список путей API, которые должны обрабатываться с префиксом /api
  const apiPaths = [
    '/chats',
    '/folders', 
    '/user',
    '/contacts',
    '/groups',
    '/channels',
    '/calls',
    '/ai',
    '/upload',
    '/send-message',
    '/chat-messages',
    '/search',
    '/connection-status',
    '/support-ticket',
    '/support-tickets',
    '/verification-status',
    '/test-s3-url',
    '/fix-old-messages',
    '/encryption-compatibility',
    '/generate-new-key',
    '/media',
    '/ping',
    '/health',
    '/register',
    '/login',
    '/reset-password',
    '/verify-reset-code',
    '/confirm-reset',
    '/send-verification-code',
    '/verify-email-code',
    '/csrf-token',
    '/debug',
    '/test',
    '/channels',
    '/groups'
  ];
  
  // Проверяем, начинается ли путь с одного из этих шаблонов
  // И при этом НЕ начинается с /api и НЕ является корневым /
  const shouldAddApi = apiPaths.some(path => req.path.startsWith(path)) && 
                       !req.path.startsWith('/api') && 
                       req.path !== '/' &&
                       !req.path.startsWith('/s3-proxy') &&
                       !req.path.startsWith('/uploads') &&
                       !req.path.startsWith('/assets') &&
                       !req.path.startsWith('/web') &&
                       !req.path.startsWith('/flutter') &&
                       !req.path.startsWith('/favicon.ico');
  
  if (shouldAddApi) {
    const originalUrl = req.url;
    req.url = `/api${req.url}`;
    console.log(`🔄 Авто-добавление /api: ${originalUrl} -> ${req.url}`);
  }
  
  next();
});

// ==================== 🔐 RATE LIMITING (ЗАЩИТА ОТ DDOS/БРУТФОРСА) ====================

// Общий лимитер для всех запросов
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { 
    success: false, 
    error: 'Слишком много запросов. Попробуйте позже.' 
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Лимитер для авторизации
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true,
  message: { 
    success: false, 
    error: 'Слишком много попыток входа. Попробуйте через 15 минут.' 
  },
  keyGenerator: (req) => {
    // Используем ipKeyGenerator для правильной обработки IPv6
    const ip = req.ip || req.connection.remoteAddress || 'unknown';
    return ip + (req.body.email || '');
  }
});

// Лимитер для регистрации
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: { 
    success: false, 
    error: 'Слишком много попыток регистрации. Попробуйте через час.' 
  }
});

// Лимитер для отправки кодов
const codeLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: { 
    success: false, 
    error: 'Слишком много запросов кода. Попробуйте через час.' 
  }
});

// Лимитер для API эндпоинтов
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  message: { 
    success: false, 
    error: 'Слишком много запросов к API. Попробуйте позже.' 
  }
});

// Применяем глобальный лимитер ко всем запросам
app.use(globalLimiter);

// ==================== 🔐 CSRF ЗАЩИТА ====================
const csrfProtection = csrf({ 
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict'
  }
});

// Эндпоинт для получения CSRF токена
app.get('/api/csrf-token', csrfProtection, (req, res) => {
  res.json({ 
    success: true, 
    csrfToken: req.csrfToken() 
  });
});

// ==================== ПАРСИНГ JSON И FORM-DATA ====================
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// ==================== ОБСЛУЖИВАНИЕ FLUTTER WEB ====================
if (fs.existsSync(WEB_DIR)) {
    app.use(express.static(WEB_DIR, {
        setHeaders: (res, filePath) => {
            if (filePath.includes('.js') || filePath.includes('.css') || filePath.includes('.wasm')) {
                res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
            }
        }
    }));
    
    if (fs.existsSync(ASSETS_DIR)) {
        app.use('/assets', express.static(ASSETS_DIR, {
            setHeaders: (res, filePath) => {
                if (filePath.endsWith('.wasm')) {
                    res.setHeader('Content-Type', 'application/wasm');
                } else if (filePath.endsWith('.js')) {
                    res.setHeader('Content-Type', 'application/javascript');
                } else if (filePath.endsWith('.css')) {
                    res.setHeader('Content-Type', 'text/css');
                }
                res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
            }
        }));
    }
    
    console.log('✅ Flutter Web настроен');
} else {
    console.log('⚠️ Flutter Web директория не найдена:', WEB_DIR);
}

// ==================== БАЗА ДАННЫХ (PostgreSQL) ====================
const pool = new Pool({
    user: 'postgres',
    password: '<Tts>]:{clPexck.W8K|6YlvCtdW?%.;',
    host: 'localhost',
    port: 5432,
    database: 'safer_chat',
    ssl: false,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000
});

pool.on('error', (err) => {
    console.error('❌ Ошибка PostgreSQL пула:', err.message);
});

pool.connect((err, client, release) => {
    if (err) {
        console.error('❌ Ошибка подключения к БД:', err.message);
        console.error('   Код ошибки:', err.code);
        console.error('   Детали:', err.detail);
        console.log('\n⚠️  Убедитесь, что:');
        console.log('   1. PostgreSQL установлен и запущен');
        console.log('   2. База данных "safer_chat" создана');
        console.log('   3. Пароль PostgreSQL указан верно');
        console.log('\n   Для создания БД выполните:');
        console.log('   createdb -U postgres safer_chat');
    } else {
        client.query('SELECT version()', (err, result) => {
            if (err) {
                console.error('❌ Ошибка запроса версии:', err.message);
            } else {
                console.log('📊 PostgreSQL версия:', result.rows[0].version);
            }
            release();
        });
    }
});

// ==================== 🔐 ЛОГИРОВАНИЕ БЕЗОПАСНОСТИ ====================

// Создаем таблицу для логов безопасности
async function createSecurityLogsTable() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS security_logs (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        action VARCHAR(50) NOT NULL,
        ip_address INET,
        user_agent TEXT,
        details JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      CREATE INDEX IF NOT EXISTS idx_security_logs_user_id ON security_logs(user_id);
      CREATE INDEX IF NOT EXISTS idx_security_logs_created_at ON security_logs(created_at);
      CREATE INDEX IF NOT EXISTS idx_security_logs_action ON security_logs(action);
    `);
    console.log('✅ Security logs table created');
  } catch (error) {
    console.error('❌ Error creating security logs table:', error);
  }
}

// Вызываем при старте
createSecurityLogsTable();

// Функция логирования безопасности
async function logSecurityEvent(userId, action, req, details = {}) {
  try {
    await pool.query(
      `INSERT INTO security_logs (user_id, action, ip_address, user_agent, details)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        userId,
        action,
        req.ip || req.connection.remoteAddress,
        req.headers['user-agent'],
        JSON.stringify(details)
      ]
    );
    
    const suspiciousActions = ['multiple_failed_logins', 'suspicious_ip', 'rate_limit_exceeded'];
    if (suspiciousActions.includes(action)) {
      console.warn(`⚠️ Suspicious activity detected: ${action} from IP ${req.ip}`);
    }
  } catch (error) {
    console.error('Error logging security event:', error);
  }
}

// ==================== 🔐 ЗАЩИТА ОТ БРУТФОРСА ====================

// Хранилище неудачных попыток
const failedAttempts = new Map();

// Middleware для проверки брутфорса
function checkBruteForce(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress;
  const email = req.body.email || 'unknown';
  const key = `${ip}:${email}`;
  
  const attempts = failedAttempts.get(key) || { count: 0, firstAttempt: Date.now() };
  
  if (Date.now() - attempts.firstAttempt > 30 * 60 * 1000) {
    failedAttempts.set(key, { count: 1, firstAttempt: Date.now() });
    return next();
  }
  
  if (attempts.count >= 10) {
    logSecurityEvent(null, 'brute_force_detected', req, { ip, email });
    return res.status(429).json({ 
      success: false, 
      error: 'Слишком много попыток. Доступ временно заблокирован.' 
    });
  }
  
  req.incrementFailedAttempts = () => {
    const current = failedAttempts.get(key) || { count: 0, firstAttempt: Date.now() };
    failedAttempts.set(key, { 
      count: current.count + 1, 
      firstAttempt: current.firstAttempt 
    });
    
    if (current.count + 1 >= 5) {
      logSecurityEvent(null, 'multiple_failed_logins', req, { 
        ip, 
        email, 
        attempts: current.count + 1 
      });
    }
  };
  
  next();
}

// ==================== NODEMAILER ====================
const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { 
        user: EMAIL_USER, 
        pass: EMAIL_PASS 
    },
});

// ==================== JWT MIDDLEWARE ====================
function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ error: 'Нет токена' });
  
  const token = authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Неверный формат токена' });
  
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch (error) {
    console.error('JWT Error:', error.message);
    res.status(401).json({ error: 'Неверный токен' });
  }
}

// ==================== S3 КЛИЕНТ ====================
const s3Client = new S3Client({
  endpoint: "http://localhost:9000",
  credentials: {
    accessKeyId: "minioadmin",
    secretAccessKey: "minioadmin"
  },
  region: "us-east-1",
  forcePathStyle: true,
  signatureVersion: 'v4'
});

// ==================== ПРОКСИ ДЛЯ S3 ФАЙЛОВ ====================
app.get('/s3-proxy/*', async (req, res) => {
  try {
    const key = req.params[0];
        
    const command = new GetObjectCommand({
      Bucket: 'safer-chat-media',
      Key: key,
    });
    
    const response = await s3Client.send(command);
    
    console.log('✅ S3 Response received:', {
      contentType: response.ContentType,
      contentLength: response.ContentLength
    });
    
    res.setHeader('Content-Type', response.ContentType || 'application/octet-stream');
    res.setHeader('Content-Length', response.ContentLength || '0');
    res.setHeader('Cache-Control', 'public, max-age=31536000');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    
    if (response.ETag) {
      res.setHeader('ETag', response.ETag);
    }
    
    if (response.Body && typeof response.Body.pipe === 'function') {
      response.Body.pipe(res);
    } else {
      const chunks = [];
      const stream = response.Body;
      
      stream.on('data', (chunk) => {
        chunks.push(chunk);
      });
      
      stream.on('end', () => {
        const buffer = Buffer.concat(chunks);
        console.log(`✅ Sending ${buffer.length} bytes`);
        res.send(buffer);
      });
      
      stream.on('error', (error) => {
        console.error('❌ Stream error:', error);
        res.status(500).json({ error: 'Stream error' });
      });
    }
    
  } catch (error) {
    console.error('❌ S3 proxy error:', {
      name: error.name,
      message: error.message,
      code: error.code
    });
    
    if (error.name === 'NoSuchKey' || error.code === 'NoSuchKey') {
      res.status(404).json({ 
        error: 'File not found in S3',
        key: req.params[0]
      });
    } else if (error.code === 'AccessDenied') {
      res.status(403).json({ 
        error: 'Access denied to S3',
        message: 'Check bucket permissions'
      });
    } else {
      res.status(500).json({ 
        error: 'S3 proxy error',
        message: error.message,
        code: error.code
      });
    }
  }
});

// ==================== ФУНКЦИИ ЗАГРУЗКИ В S3 ====================
const uploadToS3 = async (buffer, originalName, mimetype) => {
  console.log('🔥 S3 UPLOAD START:', {
    originalName,
    bufferSize: buffer?.length,
    mimetype
  });
  
  const fileExt = path.extname(originalName).toLowerCase();
  const key = `chat/${Date.now()}-${crypto.randomBytes(8).toString('hex')}${fileExt}`;
    
  try {
    let processedBuffer = buffer;
    let contentType = mimetype;
    
    if (mimetype.startsWith('image/')) {
      try {
        processedBuffer = await sharp(buffer)
          .resize(1024, 1024, { 
            fit: 'inside',
            withoutEnlargement: true 
          })
          .jpeg({ 
            quality: 85,
            mozjpeg: true 
          })
          .toBuffer();
        contentType = 'image/jpeg';
      } catch (sharpError) {
        console.warn('⚠️ Sharp processing failed, using original:', sharpError.message);
        processedBuffer = buffer;
      }
    }
    
    const uploadParams = {
      Bucket: 'safer-chat-media',
      Key: key,
      Body: processedBuffer,
      ContentType: contentType,
      ACL: 'public-read',
      Metadata: {
        'original-filename': encodeURIComponent(originalName),
        'upload-timestamp': Date.now().toString()
      }
    };
    
    await s3Client.send(new PutObjectCommand(uploadParams));
    
    const s3Url = `${BASE_URL}/s3-proxy/${key}`;
    console.log('🎉 S3 UPLOAD SUCCESS! URL:', s3Url);
    
    return s3Url;
    
  } catch (error) {
    console.error('💥 S3 UPLOAD ERROR:', error.message);
    throw new Error(`S3 upload failed: ${error.message}`);
  }
};

// ==================== ФУНКЦИЯ ЗАГРУЗКИ АВАТАРА В S3 ====================
async function uploadToS3Avatar(buffer) {
  
  try {
    if (!buffer || buffer.length === 0) {
      throw new Error('Buffer is empty');
    }
    
    const key = `avatars/${Date.now()}-${crypto.randomBytes(8).toString('hex')}.jpg`;
    
    const processedBuffer = await sharp(buffer)
      .resize(200, 200, { 
        fit: 'cover',
        position: 'center'
      })
      .jpeg({ 
        quality: 80,
        mozjpeg: true 
      })
      .toBuffer();
    
    await s3Client.send(new PutObjectCommand({
      Bucket: 'safer-chat-media',
      Key: key,
      Body: processedBuffer,
      ContentType: 'image/jpeg',
      ACL: 'public-read'
    }));
    
    const avatarUrl = `${BASE_URL}/s3-proxy/${key}`;
    
    return avatarUrl;
    
  } catch (error) {
    console.error('💥 Avatar upload error:', error);
    throw new Error(`Avatar upload failed: ${error.message}`);
  }
}

// Функция для определения типа файла
function getFileTypeId(mimetype, filename) {
    const ext = filename.split('.').pop()?.toLowerCase();
    
    if (ext === 'gif' || mimetype === 'image/gif') {
        return 6;
    }
    
    if (mimetype?.startsWith('image/')) {
        return 2;
    }
    
    if (mimetype?.startsWith('video/')) {
        return 3;
    }
    
    if (mimetype?.startsWith('audio/')) {
        return 4;
    }
    
    const imageExts = ['jpg', 'jpeg', 'png', 'bmp', 'webp', 'svg', 'ico'];
    const videoExts = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp', 'mpeg', 'mpg'];
    const audioExts = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma', 'opus'];
    
    if (imageExts.includes(ext)) {
        return 2;
    }
    if (videoExts.includes(ext)) {
        return 3;
    }
    if (audioExts.includes(ext)) {
        return 4;
    }
    
    return 5;
}

const uploadChat = multer({ 
  storage: multer.memoryStorage(),
  limits: { 
    fileSize: 100 * 1024 * 1024,
    files: 10
  },
  fileFilter: (req, file, cb) => {
    cb(null, true);
  }
});

const uploadAvatar = multer({ 
  storage: multer.memoryStorage(),
  limits: { 
    fileSize: 5 * 1024 * 1024,
    files: 1 
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Только изображения!'), false);
    }
  }
});

// ==================== ХРАНИЛИЩЕ КОДОВ ПОДТВЕРЖДЕНИЯ ====================
const verificationCodes = new Map();

// Очистка старых кодов каждые 5 минут
setInterval(() => {
    const now = Date.now();
    for (const [email, data] of verificationCodes.entries()) {
        if (data.expiresAt < now) {
            verificationCodes.delete(email);
        }
    }
}, 5 * 60 * 1000);

// ==================== ХРАНИЛИЩЕ КОДОВ СБРОСА ПАРОЛЯ ====================
const resetPasswordCodes = new Map();

// Очистка старых кодов сброса пароля каждые 5 минут
setInterval(() => {
    const now = Date.now();
    for (const [email, data] of resetPasswordCodes.entries()) {
        if (data.expiresAt < now) {
            resetPasswordCodes.delete(email);
        }
    }
}, 5 * 60 * 1000);

// ==================== 🔐 ВАЛИДАЦИЯ ДЛЯ ЭНДПОИНТОВ ====================

// Валидация для регистрации
const validateRegistration = [
  body('email')
    .trim()
    .isEmail().withMessage('Неверный формат email')
    .normalizeEmail({ gmail_remove_dots: false })
    .isLength({ max: 255 }).withMessage('Email слишком длинный')
    .customSanitizer(value => sanitizeInput(value)),
  
  body('password')
    .isLength({ min: 10 }).withMessage('Пароль должен быть минимум 10 символов')
    .custom((value) => {
      const validation = validatePasswordStrength(value);
      if (!validation.isValid) {
        throw new Error(validation.errors.join(', '));
      }
      return true;
    })
    .customSanitizer(value => sanitizeInput(value)),
  
  body('verificationCode')
    .isLength({ min: 4, max: 4 }).withMessage('Код должен быть 4 цифры')
    .isNumeric().withMessage('Код должен содержать только цифры')
    .customSanitizer(value => sanitizeInput(value)),
  
  (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        success: false, 
        errors: errors.array() 
      });
    }
    next();
  }
];

// Валидация для логина
const validateLogin = [
  body('email')
    .trim()
    .isEmail().withMessage('Неверный формат email')
    .normalizeEmail({ gmail_remove_dots: false })
    .customSanitizer(value => sanitizeInput(value)),
  
  body('password')
    .notEmpty().withMessage('Пароль обязателен')
    .customSanitizer(value => sanitizeInput(value)),
  
  (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        success: false, 
        errors: errors.array() 
      });
    }
    next();
  }
];

// ==================== ROUTES ====================

/**
 * 1. Пагинированный список чатов (для медленных соединений)
 * GET /api/chats/paginated?page=1&limit=10
 */
app.get('/api/chats/paginated', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;
    
    console.log(`📱 Пагинированный запрос чатов для ${userId}, страница ${page}`);
    
    const result = await pool.query(`
      SELECT 
        c.id, 
        c.title, 
        c.is_private, 
        c.created_at,
        c.is_pinned,
        c.is_muted,
        c.is_channel,
        (SELECT COUNT(*) FROM messages m WHERE m.chat_id = c.id) as message_count,
        (SELECT created_at FROM messages m WHERE m.chat_id = c.id ORDER BY created_at DESC LIMIT 1) as last_message_time
      FROM chats c
      WHERE c.id IN (
        SELECT chat_id FROM chat_participants WHERE user_id = $1
      ) OR c.is_private = false
      ORDER BY 
        c.is_pinned DESC,
        last_message_time DESC NULLS LAST,
        c.created_at DESC
      LIMIT $2 OFFSET $3
    `, [userId, limit, offset]);
    
    const countResult = await pool.query(`
      SELECT COUNT(*) as total
      FROM chats c
      WHERE c.id IN (
        SELECT chat_id FROM chat_participants WHERE user_id = $1
      ) OR c.is_private = false
    `, [userId]);
    
    const total = parseInt(countResult.rows[0].total);
    
    const chats = await Promise.all(result.rows.map(async (chat) => {
      const unreadResult = await pool.query(`
        SELECT COUNT(*) as unread_count
        FROM messages m
        WHERE m.chat_id = $1 
          AND m.user_id != $2
          AND m.id > COALESCE(
            (SELECT last_read_message_id FROM chat_participants 
             WHERE chat_id = $1 AND user_id = $2), 0)
      `, [chat.id, userId]);
      
      let title = chat.title;
      let recipientUserId = null;
      
      if (chat.is_private) {
        const participantResult = await pool.query(`
          SELECT u.id, u.email_encrypted, u.nickname, u.name
          FROM chat_participants cp
          JOIN users u ON cp.user_id = u.id
          WHERE cp.chat_id = $1 AND cp.user_id != $2
        `, [chat.id, userId]);
        
        if (participantResult.rows.length > 0) {
          const participant = participantResult.rows[0];
          recipientUserId = participant.id;
          
          try {
            if (participant.name) {
              const decryptedName = decryptString(participant.name);
              if (decryptedName && decryptedName.trim()) {
                title = decryptedName.trim();
              }
            }
            
            if (title === chat.title && participant.nickname) {
              const decryptedNickname = decryptString(participant.nickname);
              if (decryptedNickname && decryptedNickname.trim()) {
                title = decryptedNickname.trim();
              }
            }
            
            if (title === chat.title && participant.email_encrypted) {
              const decryptedEmail = decryptString(participant.email_encrypted);
              title = decryptedEmail.split('@')[0] || 'Пользователь';
            }
          } catch (e) {
            console.error('Error decrypting participant name:', e);
          }
        }
      }
      
      return {
        id: chat.id,
        title: title,
        is_private: chat.is_private,
        is_pinned: chat.is_pinned || false,
        is_muted: chat.is_muted || false,
        is_channel: chat.is_channel || false,
        unread_count: parseInt(unreadResult.rows[0]?.unread_count) || 0,
        message_count: parseInt(chat.message_count) || 0,
        last_message_time: chat.last_message_time,
        recipient_user_id: recipientUserId
      };
    }));
    
    res.json({
      success: true,
      chats: chats,
      pagination: {
        currentPage: page,
        totalPages: Math.ceil(total / limit),
        totalItems: total,
        hasMore: page * limit < total
      }
    });
    
  } catch (error) {
    console.error('❌ Paginated chats error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * 2. Эндпоинт для загрузки изображений с разным качеством
 * GET /api/media/:key?quality=low|medium|high
 */
app.get('/api/media/:key', async (req, res) => {
  try {
    const { key } = req.params;
    const quality = req.query.quality || 'medium';
    
    console.log(`🖼️ Запрос медиа: ${key}, качество: ${quality}`);
    
    const command = new GetObjectCommand({
      Bucket: 'safer-chat-media',
      Key: key,
    });
    
    const response = await s3Client.send(command);
    
    const buffer = await streamToBuffer(response.Body);
    
    if (response.ContentType?.startsWith('image/') && quality !== 'high') {
      let processedBuffer;
      let targetWidth, targetHeight, quality_par;
      
      if (quality === 'low') {
        targetWidth = 320;
        targetHeight = 320;
        quality_par = 30;
      } else if (quality === 'medium') {
        targetWidth = 640;
        targetHeight = 640;
        quality_par = 60;
      } else {
        targetWidth = 1024;
        targetHeight = 1024;
        quality_par = 80;
      }
      
      try {
        processedBuffer = await sharp(buffer)
          .resize(targetWidth, targetHeight, { 
            fit: 'inside',
            withoutEnlargement: true 
          })
          .jpeg({ 
            quality: quality_par,
            mozjpeg: true,
            progressive: true
          })
          .toBuffer();
        
        console.log(`✅ Изображение обработано: ${buffer.length} -> ${processedBuffer.length} bytes`);
        
        res.setHeader('Content-Type', 'image/jpeg');
        res.setHeader('X-Image-Quality', quality);
        res.setHeader('X-Original-Size', buffer.length);
        res.setHeader('Cache-Control', 'public, max-age=86400');
        res.send(processedBuffer);
      } catch (sharpError) {
        console.error('❌ Sharp processing error:', sharpError);
        res.setHeader('Content-Type', response.ContentType);
        res.setHeader('X-Image-Quality', 'original');
        res.send(buffer);
      }
    } else {
      res.setHeader('Content-Type', response.ContentType);
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.send(buffer);
    }
    
  } catch (error) {
    console.error('❌ Media error:', error);
    
    if (error.name === 'NoSuchKey') {
      res.status(404).json({ error: 'File not found' });
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

/**
 * 3. Получение только непрочитанных счетчиков (легкий запрос)
 * GET /api/chats/unread-counts
 */
app.get('/api/chats/unread-counts', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    console.log(`🔢 Запрос непрочитанных счетчиков для ${userId}`);
    
    const result = await pool.query(`
      SELECT 
        c.id,
        COUNT(m.id) as unread_count
      FROM chats c
      JOIN chat_participants cp ON c.id = cp.chat_id
      LEFT JOIN messages m ON c.id = m.chat_id 
        AND m.user_id != $1
        AND m.id > COALESCE(cp.last_read_message_id, 0)
      WHERE cp.user_id = $1
      GROUP BY c.id
    `, [userId]);
    
    const unreadCounts = {};
    let totalUnread = 0;
    
    result.rows.forEach(row => {
      const count = parseInt(row.unread_count);
      unreadCounts[row.id] = count;
      totalUnread += count;
    });
    
    res.json({
      success: true,
      unread_counts: unreadCounts,
      total_unread: totalUnread
    });
    
  } catch (error) {
    console.error('❌ Unread counts error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * 4. Проверка здоровья соединения (для измерения latency)
 * GET /health
 */
app.get('/health', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  
  res.json({ 
    status: 'ok', 
    timestamp: Date.now(),
    version: '1.0.0'
  });
});

/**
 * 5. Пинг эндпоинт для WebSocket (очень легкий)
 * GET /ping
 */
app.get('/ping', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Content-Type', 'text/plain');
  res.send('pong');
});

/**
 * 6. Получение информации о чате для быстрой загрузки (без сообщений)
 * GET /api/chats/:chatId/info
 */
app.get('/api/chats/:chatId/info', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const userId = req.user.userId;
    
    const accessCheck = await pool.query(
      'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (accessCheck.rows.length === 0 && chatId != 1) {
      return res.status(403).json({ 
        success: false, 
        error: 'Нет доступа к этому чату' 
      });
    }
    
    const chatResult = await pool.query(
      'SELECT id, title, is_private, is_channel, created_at FROM chats WHERE id = $1',
      [chatId]
    );
    
    if (chatResult.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Чат не найден' 
      });
    }
    
    const chat = chatResult.rows[0];
    let title = chat.title;
    let recipientUserId = null;
    
    if (chat.is_private) {
      const participantResult = await pool.query(`
        SELECT u.id, u.email_encrypted, u.nickname, u.name, u.avatar_url
        FROM chat_participants cp
        JOIN users u ON cp.user_id = u.id
        WHERE cp.chat_id = $1 AND cp.user_id != $2
      `, [chatId, userId]);
      
      if (participantResult.rows.length > 0) {
        const participant = participantResult.rows[0];
        recipientUserId = participant.id;
        
        try {
          if (participant.name) {
            const decryptedName = decryptString(participant.name);
            if (decryptedName && decryptedName.trim()) {
              title = decryptedName.trim();
            }
          }
          
          if (title === chat.title && participant.nickname) {
            const decryptedNickname = decryptString(participant.nickname);
            if (decryptedNickname && decryptedNickname.trim()) {
              title = decryptedNickname.trim();
            }
          }
          
          if (title === chat.title && participant.email_encrypted) {
            const decryptedEmail = decryptString(participant.email_encrypted);
            title = decryptedEmail.split('@')[0] || 'Пользователь';
          }
        } catch (e) {
          console.error('Error decrypting participant name:', e);
        }
      }
    }
    
    res.json({
      success: true,
      chat: {
        id: chat.id,
        title: title,
        is_private: chat.is_private,
        is_channel: chat.is_channel,
        created_at: chat.created_at,
        recipient_user_id: recipientUserId
      }
    });
    
  } catch (error) {
    console.error('❌ Chat info error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// Helper для преобразования stream в buffer
async function streamToBuffer(stream) {
  const chunks = [];
  return new Promise((resolve, reject) => {
    stream.on('data', chunk => chunks.push(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

/**
 * 7. Получение статуса соединения (для клиента)
 * GET /api/connection-status
 */
app.get('/api/connection-status', (req, res) => {
  res.json({
    success: true,
    timestamp: Date.now(),
    server_time: new Date().toISOString(),
    websocket: {
      enabled: true,
      path: '/ws'
    },
    features: {
      paginated_chats: true,
      adaptive_media: true,
      compression: true
    }
  });
});

// 1. Главная страница
app.get('/', (req, res) => {
    if (fs.existsSync(path.join(WEB_DIR, 'index.html'))) {
        res.sendFile(path.join(WEB_DIR, 'index.html'));
    } else {
        res.json({ 
            message: 'SaferChat API Server (Local Development)', 
            status: 'running',
            endpoints: [
                '/api/send-verification-code',
                '/api/verify-email-code',
                '/api/register', 
                '/api/login',
                '/api/reset-password',
                '/api/verify-reset-code',
                '/api/confirm-reset',
                '/api/chats/paginated',
                '/api/media/:key',
                '/api/chats/unread-counts',
                '/health',
                '/ping',
                '/api/chats/:chatId/info',
                '/api/connection-status'
            ]
        });
    }
});

// 2. Health check
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        timestamp: new Date().toISOString(),
        service: 'saferchat-api-local',
        version: '1.0.0-local',
        environment: 'development'
    });
});

// 3. POST Отправка кода подтверждения на email (регистрация И смена email)
app.post('/api/send-verification-code', codeLimiter, async (req, res) => {
    const { email, isEmailChange } = req.body;
    
    if (!email) {
        return res.status(400).json({ error: 'Укажите email' });
    }
    
    const cleanEmail = sanitizeInput(email).toLowerCase();
    
    if (!isValidEmail(cleanEmail)) {
        return res.status(400).json({ error: 'Неверный формат email' });
    }
    
    const mapKey = getMapKey(cleanEmail);
    
    try {
        const emailHash = hashEmail(cleanEmail);
        
        let currentUserId = null;
        if (isEmailChange) {
            const token = req.headers.authorization?.replace('Bearer ', '');
            if (!token) {
                return res.status(401).json({ error: 'Требуется авторизация' });
            }
            
            try {
                const decoded = jwt.verify(token, JWT_SECRET);
                currentUserId = decoded.userId;
            } catch (err) {
                return res.status(401).json({ error: 'Неверный токен' });
            }
        }
        
        const existing = await pool.query(
            'SELECT id FROM users WHERE email_hash = $1', 
            [emailHash]
        );
        
        if (existing.rows.length > 0) {
            if (!isEmailChange || existing.rows[0].id !== currentUserId) {
                await logSecurityEvent(currentUserId, 'email_already_exists', req, { email: cleanEmail });
                return res.status(400).json({ error: 'email_exists' });
            }
        }
        
        const code = generateVerificationCode();
        const expiresAt = Date.now() + 5 * 60 * 1000;
        
        verificationCodes.set(mapKey, {
            code,
            expiresAt,
            attempts: 0,
            verified: false,
            userId: currentUserId,
            isEmailChange: isEmailChange || false,
            originalEmail: cleanEmail
        });
                
        try {
            const mailOptions = {
                from: `"Safer Chat" <${EMAIL_USER}>`,
                to: cleanEmail,
                subject: isEmailChange 
                    ? 'Подтверждение смены email в Safer Chat'
                    : 'Ваш код подтверждения для регистрации в Safer Chat',
                text: `Ваш код подтверждения: ${code}\n\nКод действителен в течение 5 минут.`,
                html: `
                    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
                        <h2 style="color: #4CAF50; text-align: center;">Safer Chat</h2>
                        <h3 style="color: #333;">${isEmailChange ? 'Подтверждение смены email' : 'Подтверждение регистрации'}</h3>
                        <p>Здравствуйте!</p>
                        <p>${isEmailChange 
                            ? 'Вы запросили смену email в Safer Chat. Для подтверждения введите следующий код:'
                            : 'Вы начали процесс регистрации в Safer Chat. Для завершения регистрации введите следующий код подтверждения:'
                        }</p>
                        <div style="background-color: #f5f5f5; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 8px; margin: 25px 0; border-radius: 8px; border: 2px dashed #4CAF50;">
                            ${code}
                        </div>
                        <p style="color: #666; font-size: 14px; line-height: 1.5;">
                            <strong>Важно:</strong> Этот код будет действителен в течение <strong>5 минут</strong>.<br>
                            Если вы не запрашивали этот код, просто проигнорируйте это письмо${isEmailChange ? ' и немедленно смените пароль в настройках безопасности' : ''}.
                        </p>
                        <hr style="border: none; border-top: 1px solid #eee; margin: 25px 0;">
                        <p style="color: #999; font-size: 12px; text-align: center;">
                            Это автоматическое сообщение. Пожалуйста, не отвечайте на него.<br>
                            © ${new Date().getFullYear()} Safer Chat. Все права защищены.
                        </p>
                    </div>
                `
            };
            
            await transporter.sendMail(mailOptions);
            
        } catch (emailError) {
            console.error('❌ Ошибка отправки email:', emailError);
            await logSecurityEvent(currentUserId, 'email_send_failed', req, { error: emailError.message });
        }
        
        res.json({ 
            success: true, 
            message: 'Код подтверждения отправлен на email',
            expiresIn: 300
        });
        
    } catch (error) {
        console.error('Send verification code error:', error);
        await logSecurityEvent(null, 'send_code_error', req, { error: error.message });
        res.status(500).json({ 
            error: 'Ошибка отправки кода подтверждения'
        });
    }
});

// 4. POST Проверка кода подтверждения email (регистрация И смена email)
app.post('/api/verify-email-code', async (req, res) => {
    const { email, code, isEmailChange } = req.body;
    
    if (!email || !code) {
        return res.status(400).json({ error: 'Укажите email и код' });
    }
    
    try {
        const cleanEmail = sanitizeInput(email).toLowerCase();
        const mapKey = getMapKey(cleanEmail);
        
        const verificationData = verificationCodes.get(mapKey);
        
        if (!verificationData) {
            return res.status(400).json({ 
                success: false,
                error: 'Код не найден или срок действия истек. Запросите новый код.' 
            });
        }
        
        if (Date.now() > verificationData.expiresAt) {
            verificationCodes.delete(mapKey);
            return res.status(400).json({ 
                success: false,
                error: 'Срок действия кода истек. Запросите новый код.' 
            });
        }
        
        if (verificationData.code !== code) {
            verificationData.attempts += 1;
            
            if (verificationData.attempts >= 5) {
                verificationCodes.delete(mapKey);
                return res.status(400).json({ 
                    success: false,
                    error: 'Слишком много неудачных попыток. Запросите новый код.' 
                });
            }
            
            return res.status(400).json({ 
                success: false,
                error: 'Неверный код подтверждения',
                remainingAttempts: 5 - verificationData.attempts
            });
        }
        
        if (isEmailChange && verificationData.isEmailChange) {
            const token = req.headers.authorization?.replace('Bearer ', '');
            if (!token) {
                return res.status(401).json({ error: 'Требуется авторизация' });
            }
            
            try {
                const decoded = jwt.verify(token, JWT_SECRET);
                const userId = decoded.userId;
                
                if (verificationData.userId !== userId) {
                    return res.status(403).json({ error: 'Недостаточно прав' });
                }
                
                const emailHash = hashEmail(cleanEmail);
                const encryptedEmail = encryptString(cleanEmail);
                
                await pool.query(
                    'UPDATE users SET email_encrypted = $1, email_hash = $2 WHERE id = $3',
                    [encryptedEmail, emailHash, userId]
                );
                
                console.log(`✅ Email пользователя ${userId} успешно изменён на ${cleanEmail}`);
                verificationCodes.delete(mapKey);
                
                return res.json({ 
                    success: true,
                    message: 'Email успешно изменён',
                    emailChanged: true
                });
                
            } catch (err) {
                console.error('❌ Ошибка при смене email:', err);
                return res.status(500).json({ error: 'Ошибка обновления email' });
            }
        }
        
        verificationData.verified = true;
        verificationData.verifiedAt = Date.now();
        
        res.json({ 
            success: true,
            message: 'Email успешно подтвержден',
            verifiedAt: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('Verify email code error:', error);
        res.status(500).json({ 
            error: 'Ошибка проверки кода',
            details: error.message
        });
    }
});

// 5. POST Регистрация - ОБНОВЛЕННАЯ ВЕРСИЯ
app.post('/api/register', registerLimiter, validateRegistration, async (req, res) => {
    const { email, password, verificationCode, name, nickname } = req.body;

    console.log('=== REGISTER START ===');
    console.log('EMAIL FROM REQUEST:', email);
    console.log('CODE FROM REQUEST:', verificationCode);
    console.log('verificationCodes keys:', [...verificationCodes.keys()]);
    console.log('RAW BODY:', req.body);
    
    try {
        const cleanEmail = sanitizeInput(email).toLowerCase();
        const cleanPassword = sanitizeInput(password);
        const cleanCode = sanitizeInput(verificationCode);
        
        const mapKey = getMapKey(cleanEmail);
        
        const emailHash = hashEmail(cleanEmail);
        const encryptedEmail = encryptString(cleanEmail);
        const encryptedName = name ? encryptString(sanitizeInput(name)) : null;
        const encryptedNickname = nickname ? encryptString(sanitizeInput(nickname)) : null;
        
        const existing = await pool.query(
            'SELECT * FROM users WHERE email_hash = $1', 
            [emailHash]
        );
        
        if (existing.rows.length > 0) {
            await logSecurityEvent(null, 'registration_email_exists', req, { email: cleanEmail });
            return res.status(400).json({ error: 'email_exists' });
        }
        
        const verificationData = verificationCodes.get(mapKey);
        
        if (!verificationData || !verificationData.verified || verificationData.code !== cleanCode) {
            await logSecurityEvent(null, 'invalid_verification_code', req, { email: cleanEmail });
            return res.status(400).json({ 
                error: 'invalid_code',
                message: 'Неверный код подтверждения.' 
            });
        }
        
        if (Date.now() > verificationData.expiresAt) {
            verificationCodes.delete(mapKey);
            return res.status(400).json({ 
                error: 'invalid_code',
                message: 'Срок действия кода истек. Запросите новый код.' 
            });
        }
        
        const hashedPassword = await bcrypt.hash(cleanPassword, 12);
        
        const result = await pool.query(
            `INSERT INTO users (email_encrypted, email_hash, password, is_verified, created_at, name, nickname) 
             VALUES ($1, $2, $3, true, NOW(), $4, $5) 
             RETURNING id, email_encrypted, created_at, name, nickname`,
            [encryptedEmail, emailHash, hashedPassword, encryptedName, encryptedNickname]
        );
        
        const user = result.rows[0];
        const decryptedEmail = decryptString(user.email_encrypted);
        const decryptedName = user.name ? decryptString(user.name) : null;
        const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
        
        const token = jwt.sign(
            { 
                userId: user.id, 
                email: decryptedEmail 
            }, 
            JWT_SECRET, 
            { expiresIn: '30d' }
        );
        
        verificationCodes.delete(mapKey);
        
        await logSecurityEvent(user.id, 'registration_success', req, { email: decryptedEmail });
        
        res.json({ 
            success: true, 
            token,
            user: {
                id: user.id,
                email: decryptedEmail,
                name: decryptedName,
                nickname: decryptedNickname,
                createdAt: user.created_at
            },
            message: 'Регистрация успешно завершена'
        });
        
    } catch (error) {
        console.error('Register error:', error);
        await logSecurityEvent(null, 'registration_error', req, { error: error.message });
        res.status(500).json({ 
            error: 'Ошибка сервера'
        });
    }
});

// 6. POST Авторизация
app.post('/api/login', authLimiter, validateLogin, checkBruteForce, async (req, res) => {
    try {
        const { email, password } = req.body;
        
        const cleanEmail = sanitizeInput(email).toLowerCase();
        const cleanPassword = sanitizeInput(password);
        
        const emailHash = hashEmail(cleanEmail);
        
        const result = await pool.query(
            'SELECT id, email_encrypted, password, name, nickname FROM users WHERE email_hash = $1',
            [emailHash]
        );
        
        if (result.rows.length === 0) {
            req.incrementFailedAttempts();
            await logSecurityEvent(null, 'login_failed_user_not_found', req, { email: cleanEmail });
            return res.status(400).json({ error: 'Неверный email или пароль' });
        }
        
        const user = result.rows[0];
        
        const match = await bcrypt.compare(cleanPassword, user.password);
        if (!match) {
            req.incrementFailedAttempts();
            await logSecurityEvent(user.id, 'login_failed_wrong_password', req, { email: cleanEmail });
            return res.status(400).json({ error: 'Неверный email или пароль' });
        }
        
        const decryptedEmail = decryptString(user.email_encrypted);
        const decryptedName = user.name ? decryptString(user.name) : null;
        const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
        
        const token = jwt.sign(
            { userId: user.id, email: decryptedEmail }, 
            JWT_SECRET, 
            { expiresIn: '30d' }
        );
        
        const ip = req.ip || req.connection.remoteAddress;
        failedAttempts.delete(`${ip}:${cleanEmail}`);
        
        await logSecurityEvent(user.id, 'login_success', req, { email: decryptedEmail });
        
        res.json({ 
            success: true, 
            token, 
            userId: user.id,
            email: decryptedEmail,
            name: decryptedName,
            nickname: decryptedNickname
        });
        
    } catch (error) {
        console.error('Login error:', error);
        await logSecurityEvent(null, 'login_error', req, { error: error.message });
        res.status(500).json({ error: 'Ошибка сервера' });
    }
});

// 7. POST Сброс пароля (ОТПРАВКА КОДА)
app.post('/api/reset-password', codeLimiter, async (req, res) => {
    console.log('📧 POST /api/reset-password called');
    console.log('📧 Request body:', req.body);
    
    const { email } = req.body;
    
    if (!email) {
        console.log('❌ Email is missing');
        return res.status(400).json({ error: 'Укажите email' });
    }

    const cleanEmail = sanitizeInput(email).toLowerCase();
    
    if (!isValidEmail(cleanEmail)) {
        return res.status(400).json({ error: 'Неверный формат email' });
    }
    
    console.log('📧 Clean email:', cleanEmail);
    
    try {
        const emailHash = hashEmail(cleanEmail);
        console.log('🔑 Email hash:', emailHash);
        
        const result = await pool.query(
            'SELECT id, email_encrypted FROM users WHERE email_hash = $1',
            [emailHash]
        );
        
        console.log('📊 Query result:', {
            rowsFound: result.rows.length,
            hasEmailEncrypted: result.rows.length > 0 && !!result.rows[0].email_encrypted
        });
        
        if (result.rows.length === 0) {
            console.log('❌ No user found with hash:', emailHash);
            return res.status(404).json({ 
                success: false,
                error: 'Пользователь не найден',
                message: 'Пользователь с таким email не зарегистрирован'
            });
        }

        const user = result.rows[0];
        console.log('✅ User found by hash:', { id: user.id });
        
        if (!user.email_encrypted) {
            console.log('❌ User has no encrypted email');
            return res.status(404).json({ 
                success: false,
                error: 'Пользователь не найден',
                message: 'Ошибка данных пользователя'
            });
        }
        
        console.log('🔓 Decrypting email...');
        let decryptedEmail;
        try {
            decryptedEmail = decryptString(user.email_encrypted);
            console.log('✅ Decrypted email:', decryptedEmail);
        } catch (decryptError) {
            console.error('❌ Error decrypting email:', decryptError);
            return res.status(500).json({ 
                success: false,
                error: 'Ошибка проверки пользователя',
                message: 'Ошибка обработки данных'
            });
        }
        
        if (decryptedEmail.toLowerCase().trim() !== cleanEmail) {
            console.log('❌ Email mismatch!');
            console.log('   - Expected:', cleanEmail);
            console.log('   - Actual:', decryptedEmail);
            return res.status(404).json({ 
                success: false,
                error: 'Пользователь не найден',
                message: 'Email не совпадает'
            });
        }
        
        console.log('✅ Email verification passed');
        
        const code = generateVerificationCode();
        const expiresAt = Date.now() + 5 * 60 * 1000;
        
        console.log('📝 Generated code:', code);
        
        const mapKey = getMapKey(cleanEmail);
        resetPasswordCodes.set(mapKey, {
            code,
            expiresAt,
            attempts: 0,
            verified: false,
            userId: user.id,
            originalEmail: cleanEmail
        });
        
        console.log('💾 Saved to resetPasswordCodes');
        
        console.log('📧 Preparing to send email...');
        
        if (!EMAIL_USER || !EMAIL_PASS) {
            console.log('⚠️ Email credentials not set. Returning code in response.');
            return res.json({ 
                success: true, 
                message: 'Код для сброса пароля (DEV MODE)',
                code: code,
                expiresIn: 300,
                development: true
            });
        }
        
        try {
            const mailOptions = {
                from: `"Safer Chat" <${EMAIL_USER}>`,
                to: cleanEmail,
                subject: 'Сброс пароля Safer Chat',
                text: `Ваш код для сброса пароля: ${code}\n\nКод действителен в течение 5 минут.`,
                html: `
                    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
                        <h2 style="color: #4CAF50; text-align: center;">Safer Chat</h2>
                        <h3 style="color: #333;">Сброс пароля</h3>
                        <p>Здравствуйте!</p>
                        <p>Вы запросили сброс пароля для вашего аккаунта в Safer Chat. Для сброса пароля введите следующий код:</p>
                        <div style="background-color: #f5f5f5; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 8px; margin: 25px 0; border-radius: 8px; border: 2px dashed #4CAF50;">
                            ${code}
                        </div>
                        <p style="color: #666; font-size: 14px; line-height: 1.5;">
                            <strong>Важно:</strong> Этот код будет действителен в течение <strong>5 минут</strong>.<br>
                            Если вы не запрашивали сброс пароля, просто проигнорируйте это письмо.
                        </p>
                        <hr style="border: none; border-top: 1px solid #eee; margin: 25px 0;">
                        <p style="color: #999; font-size: 12px; text-align: center;">
                            Это автоматическое сообщение. Пожалуйста, не отвечайте на него.<br>
                            © ${new Date().getFullYear()} Safer Chat. Все права защищены.
                        </p>
                    </div>
                `
            };
            
            console.log('📤 Sending email to:', cleanEmail);
            const info = await transporter.sendMail(mailOptions);
            console.log('✅ Email sent! Message ID:', info.messageId);
            
            res.json({ 
                success: true, 
                message: 'Код для сброса пароля отправлен на email',
                expiresIn: 300
            });
            
        } catch (emailError) {
            console.error('❌ Email sending error:', emailError);
            
            return res.json({ 
                success: true, 
                message: 'Код для сброса пароля (EMAIL ERROR)',
                code: code,
                expiresIn: 300,
                emailError: emailError.message,
                development: true
            });
        }
        
    } catch (error) {
        console.error('❌ Reset password error:', error);
        console.error('❌ Error stack:', error.stack);
        res.status(500).json({ 
            success: false,
            error: 'Ошибка сброса пароля',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
});

// 8. POST Верификация кода сброса пароля 
app.post('/api/verify-reset-code', async (req, res) => {
    console.log('🔐 POST /api/verify-reset-code called');
    console.log('🔐 Request body:', req.body);
    
    const { code, email } = req.body;
    
    if (!code) {
        console.log('❌ Code is missing');
        return res.status(400).json({ error: 'Укажите код' });
    }
    
    if (!email) {
        console.log('❌ Email is missing');
        return res.status(400).json({ error: 'Укажите email' });
    }

    const cleanEmail = sanitizeInput(email).toLowerCase();
    console.log('📧 Normalized email:', cleanEmail);
    console.log('🔢 Code:', code);
    
    try {
        console.log('🔍 Looking for reset data for email:', cleanEmail);
        const mapKey = getMapKey(cleanEmail);
        const resetData = resetPasswordCodes.get(mapKey);
        
        if (!resetData) {
            console.log('❌ No reset data found for email:', cleanEmail);
            console.log('📋 Current resetPasswordCodes:', Array.from(resetPasswordCodes.entries()));
            return res.status(400).json({ error: 'Неверный или просроченный код' });
        }
        
        console.log('✅ Reset data found:', {
            code: resetData.code,
            expiresAt: new Date(resetData.expiresAt).toISOString(),
            attempts: resetData.attempts,
            verified: resetData.verified,
            userId: resetData.userId
        });
        
        const now = Date.now();
        const expiresAt = resetData.expiresAt;
        console.log('⏰ Time check:', {
            now: new Date(now).toISOString(),
            expiresAt: new Date(expiresAt).toISOString(),
            isExpired: now > expiresAt
        });
        
        if (now > expiresAt) {
            console.log('❌ Code expired');
            resetPasswordCodes.delete(mapKey);
            return res.status(400).json({ error: 'Срок действия кода истек. Запросите новый код.' });
        }
        
        console.log('🔢 Code comparison:', {
            expected: resetData.code,
            received: code,
            match: resetData.code === code
        });
        
        if (resetData.code !== code) {
            resetData.attempts += 1;
            console.log('❌ Wrong code. Attempt:', resetData.attempts);
            
            if (resetData.attempts >= 5) {
                console.log('❌ Too many attempts, deleting code');
                resetPasswordCodes.delete(mapKey);
                return res.status(400).json({ error: 'Слишком много неудачных попыток. Запросите новый код.' });
            }
            
            const remainingAttempts = 5 - resetData.attempts;
            console.log('⚠️ Remaining attempts:', remainingAttempts);
            
            return res.status(400).json({ 
                error: 'Неверный код',
                remainingAttempts: remainingAttempts
            });
        }
        
        console.log('✅ Code is correct! Marking as verified');
        resetData.verified = true;
        resetData.verifiedAt = now;
        
        res.json({ 
            success: true, 
            message: 'Код подтвержден',
            email: cleanEmail,
            userId: resetData.userId
        });
        
    } catch (error) {
        console.error('❌ Verify code error:', error);
        console.error('❌ Error stack:', error.stack);
        res.status(500).json({ error: 'Ошибка проверки кода' });
    }
});

// 9. POST Подтверждение сброса пароля
app.post('/api/confirm-reset', async (req, res) => {
    const { code, newPassword, email } = req.body;
    
    if (!code || !newPassword || !email) {
        return res.status(400).json({ 
            success: false,
            error: 'Укажите код, новый пароль и email' 
        });
    }

    try {
        const cleanEmail = sanitizeInput(email).toLowerCase();
        
        if (!isValidEmail(cleanEmail)) {
            return res.status(400).json({ error: 'Неверный формат email' });
        }
        
        const passwordValidation = validatePasswordStrength(newPassword);
        if (!passwordValidation.isValid) {
            return res.status(400).json({ 
                success: false,
                error: passwordValidation.errors.join(', ') 
            });
        }
        
        const mapKey = getMapKey(cleanEmail);
        const resetData = resetPasswordCodes.get(mapKey);
        
        if (!resetData) {
            return res.status(400).json({ 
                success: false,
                error: 'Неверный или просроченный код' 
            });
        }
        
        if (!resetData.verified || resetData.code !== code) {
            return res.status(400).json({ 
                success: false,
                error: 'Неверный код подтверждения' 
            });
        }
        
        if (Date.now() > resetData.expiresAt) {
            resetPasswordCodes.delete(mapKey);
            return res.status(400).json({ 
                success: false,
                error: 'Срок действия кода истек. Запросите новый код.' 
            });
        }

        const hashedPassword = await bcrypt.hash(newPassword, 12);
        
        const emailHash = hashEmail(cleanEmail);
        
        const updateResult = await pool.query(
            'UPDATE users SET password = $1 WHERE email_hash = $2 RETURNING id',
            [hashedPassword, emailHash]
        );
        
        if (updateResult.rowCount === 0) {
            return res.status(404).json({ 
                success: false,
                error: 'Пользователь не найден' 
            });
        }

        resetPasswordCodes.delete(mapKey);

        res.json({ 
            success: true, 
            message: 'Пароль успешно изменен' 
        });
    } catch (error) {
        console.error('Confirm reset error:', error);
        res.status(500).json({ 
            success: false,
            error: 'Ошибка смены пароля',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
});

// 10. GET Получение чатов
app.get('/api/chats', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    console.log(`🔍 Запрос чатов для пользователя ${userId}`);
    
    const result = await pool.query(`
      SELECT 
        c.id, 
        c.title, 
        c.is_private, 
        c.created_at,
        c.is_pinned,
        c.is_muted,
        COUNT(DISTINCT m.id) as message_count,
        MAX(m.created_at) as last_message_time,
        (SELECT m2.id
         FROM messages m2 
         WHERE m2.chat_id = c.id 
         ORDER BY m2.created_at DESC 
         LIMIT 1) as last_message_id,
        cp.last_read_message_id
      FROM chats c
      LEFT JOIN messages m ON c.id = m.chat_id
      LEFT JOIN chat_participants cp ON c.id = cp.chat_id AND cp.user_id = $1
      WHERE c.id IN (
        SELECT chat_id FROM chat_participants WHERE user_id = $1
      ) 
      OR c.is_private = false
      GROUP BY c.id, c.title, c.is_private, c.created_at, c.is_pinned, c.is_muted, cp.last_read_message_id
      ORDER BY last_message_time DESC NULLS LAST, c.created_at DESC
    `, [userId]);
    
    console.log(`📊 Найдено чатов: ${result.rows.length}`);
    
    const chatsWithDetails = await Promise.all(result.rows.map(async (chat) => {
      try {
        const unreadResult = await pool.query(`
          SELECT COUNT(*) as unread_count
          FROM messages m
          WHERE m.chat_id = $1 
            AND m.user_id != $2
            AND (m.id > $3 OR $3 IS NULL)
        `, [chat.id, userId, chat.last_read_message_id]);
        
        const unreadCount = parseInt(unreadResult.rows[0]?.unread_count) || 0;
        
        let lastMessageText = null;
        if (chat.last_message_id) {
          try {
            const messageResult = await pool.query(`
              SELECT text, file_url 
              FROM messages 
              WHERE id = $1
            `, [chat.last_message_id]);
            
            if (messageResult.rows.length > 0) {
              const msg = messageResult.rows[0];
              
              if (msg.file_url) {
                lastMessageText = '📎 Медиа';
              } else if (msg.text) {
                try {
                  const decryptedText = decryptMessage(msg.text);
                  
                  if (decryptedText && decryptedText.trim().length > 0) {
                    lastMessageText = decryptedText.length > 50 
                      ? decryptedText.substring(0, 50) + '...' 
                      : decryptedText;
                  } else {
                    lastMessageText = 'Сообщение';
                  }
                } catch (decryptError) {
                  console.error(`❌ Ошибка расшифровки сообщения для чата ${chat.id}:`, decryptError.message);
                  lastMessageText = 'Сообщение';
                }
              } else {
                lastMessageText = null;
              }
            }
          } catch (msgError) {
            console.error(`⚠️ Ошибка получения последнего сообщения для чата ${chat.id}:`, msgError.message);
            lastMessageText = 'Сообщение';
          }
        }
        
        if (chat.is_private) {
          const participantResult = await pool.query(`
            SELECT u.id, u.email_encrypted, u.nickname, u.name, u.birthday
            FROM chat_participants cp
            JOIN users u ON cp.user_id = u.id
            WHERE cp.chat_id = $1 AND cp.user_id != $2
          `, [chat.id, userId]);
          
          if (participantResult.rows.length > 0) {
            const participant = participantResult.rows[0];
            
            let displayName = '';
            
            try {
              if (participant.name) {
                displayName = decryptString(participant.name);
              }
            } catch (decryptError) {
              console.error(`❌ Ошибка расшифровки имени для пользователя ${participant.id}:`, decryptError.message);
            }
            
            if (!displayName || displayName.trim().length === 0) {
              if (participant.nickname) {
                try {
                  displayName = decryptString(participant.nickname);
                } catch (decryptError) {
                  console.error(`❌ Ошибка расшифровки никнейма для пользователя ${participant.id}:`, decryptError.message);
                  displayName = '';
                }
              }
              
              if (!displayName || displayName.trim().length === 0) {
                try {
                  const decryptedEmail = decryptString(participant.email_encrypted);
                  displayName = decryptedEmail.split('@')[0] || 'Пользователь';
                } catch (emailError) {
                  displayName = 'Пользователь';
                }
              }
            }
            
            let finalDisplayName = displayName;
            try {
              const contactResult = await pool.query(`
                SELECT contact_name 
                FROM user_contacts 
                WHERE user_id = $1 AND contact_user_id = $2
              `, [userId, participant.id]);
              
              if (contactResult.rows.length > 0 && contactResult.rows[0].contact_name) {
                finalDisplayName = contactResult.rows[0].contact_name;
                console.log(`✅ Для чата ${chat.id} используем имя из контактов: ${finalDisplayName}`);
              } else {
                console.log(`✅ Для чата ${chat.id} используем имя пользователя: ${finalDisplayName}`);
              }
            } catch (contactError) {
              console.error(`⚠️ Ошибка проверки контакта:`, contactError.message);
            }
            
            return {
              id: chat.id,
              title: finalDisplayName,
              is_private: chat.is_private,
              is_pinned: chat.is_pinned || false,
              is_muted: chat.is_muted || false,
              participant_id: participant.id,
              message_count: parseInt(chat.message_count) || 0,
              unread_count: unreadCount,
              last_message: lastMessageText,
              last_message_time: chat.last_message_time,
              created_at: chat.created_at,
              user_name: displayName,
              user_nickname: participant.nickname ? decryptString(participant.nickname) : null,
              user_birthday: participant.birthday
            };
          }
          
          console.warn(`⚠️ Участник не найден для приватного чата ${chat.id}`);
          return null;
        }
        
        return {
          id: chat.id,
          title: chat.title,
          is_private: chat.is_private,
          is_pinned: chat.is_pinned || false,
          is_muted: chat.is_muted || false,
          message_count: parseInt(chat.message_count) || 0,
          unread_count: unreadCount,
          last_message: lastMessageText,
          last_message_time: chat.last_message_time,
          created_at: chat.created_at
        };
      } catch (chatError) {
        console.error(`❌ Ошибка обработки чата ${chat.id}:`, chatError.message);
        return null;
      }
    }));
    
    const validChats = chatsWithDetails.filter(chat => chat !== null);
    
    console.log(`✅ Возвращаем ${validChats.length} валидных чатов`);
    
    res.json({
      success: true,
      chats: validChats,
      count: validChats.length
    });
    
  } catch (error) {
    console.error('❌ Get chats error:', error);
    console.error('❌ Stack trace:', error.stack);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка получения чатов',
      details: error.message 
    });
  }
});

// POST Обновление прочитанных сообщений
app.post('/api/chats/:chatId/mark-read', authMiddleware, async (req, res) => {
  try {
    const chatId = Number(req.params.chatId);
    const userId = req.user.userId;

    const last = await pool.query(
      `SELECT id FROM messages
       WHERE chat_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [chatId]
    );

    if (last.rows.length === 0) {
      return res.json({ success: true });
    }

    await pool.query(
      `UPDATE chat_participants
       SET last_read_message_id = $1
       WHERE chat_id = $2 AND user_id = $3`,
      [last.rows[0].id, chatId, userId]
    );

    res.json({ success: true });
  } catch (e) {
    console.error('mark-read error', e);
    res.status(500).json({ error: 'mark-read failed' });
  }
});

// ✨ НОВОЕ: Закрепить/открепить чат
app.patch('/api/chats/:chatId/pin', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { is_pinned } = req.body;
  const userId = req.user.userId;

  try {
    const participantCheck = await pool.query(
      'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (participantCheck.rows.length === 0) {
      return res.status(403).json({ error: 'У вас нет доступа к этому чату' });
    }

    await pool.query(
      'UPDATE chats SET is_pinned = $1 WHERE id = $2',
      [is_pinned, chatId]
    );

    console.log(`✅ Чат ${chatId} ${is_pinned ? 'закреплен' : 'откреплен'} пользователем ${userId}`);

    res.json({ success: true, is_pinned });
  } catch (error) {
    console.error('❌ Pin chat error:', error);
    res.status(500).json({ error: 'Ошибка обновления чата' });
  }
});

// ✨ НОВОЕ: Включить/выключить уведомления чата
app.patch('/api/chats/:chatId/mute', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { is_muted } = req.body;
  const userId = req.user.userId;

  try {
    const participantCheck = await pool.query(
      'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (participantCheck.rows.length === 0) {
      return res.status(403).json({ error: 'У вас нет доступа к этому чату' });
    }

    await pool.query(
      'UPDATE chats SET is_muted = $1 WHERE id = $2',
      [is_muted, chatId]
    );

    res.json({ success: true, is_muted });
  } catch (error) {
    console.error('❌ Mute chat error:', error);
    res.status(500).json({ error: 'Ошибка обновления чата' });
  }
});

// ✨ НОВЫЙ ЭНДПОИНТ: Получение потенциальных контактов
app.get('/api/contacts/available', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.userId;
        
        console.log(`🔍 Запрос доступных контактов для пользователя ${userId}`);
        
        const availableUsers = await pool.query(`
            SELECT u.id, u.email_encrypted, u.nickname
            FROM users u
            WHERE u.id != $1 
            AND u.id NOT IN (
                SELECT DISTINCT cp2.user_id 
                FROM chat_participants cp1
                JOIN chat_participants cp2 ON cp1.chat_id = cp2.chat_id
                JOIN chats c ON cp1.chat_id = c.id
                WHERE cp1.user_id = $1 
                AND cp2.user_id != $1
                AND c.is_private = true
            )
            ORDER BY u.id ASC
        `, [userId]);
        
        const contacts = availableUsers.rows.map(user => {
            const decryptedEmail = decryptString(user.email_encrypted);
            const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
            return {
                id: user.id,
                email: decryptedEmail,
                nickname: decryptedNickname,
                display_name: decryptedNickname || decryptedEmail
            };
        });
                
        res.json({
            success: true,
            contacts: contacts,
            count: contacts.length
        });
        
    } catch (error) {
        console.error('❌ Get available contacts error:', error);
        res.status(500).json({ error: 'Ошибка получения контактов' });
    }
});


// 11. Сообщения чата
app.get('/api/chat-messages', authMiddleware, async (req, res) => {
    try {
        const chatId = req.query.chat_id || req.query.chatid;
        const user_id = req.query.user_id;
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 20;
        const offset = (page - 1) * limit;
        
        console.log('📨 Получение сообщений:', {
            chat_id: chatId,
            user_id: user_id,
            page: page,
            limit: limit,
            queryParams: req.query
        });
        
        const userId = req.user.userId;
        
        let finalChatId = chatId;
        
        if ((!chatId || chatId == 0) && user_id) {
            console.log('🔍 Поиск существующего приватного чата между', userId, 'и', user_id);
            
            const existingChat = await pool.query(`
                SELECT c.id FROM chats c
                JOIN chat_participants cp1 ON c.id = cp1.chat_id
                JOIN chat_participants cp2 ON c.id = cp2.chat_id
                WHERE cp1.user_id = $1 
                  AND cp2.user_id = $2 
                  AND c.is_private = true
                LIMIT 1
            `, [userId, user_id]);
            
            if (existingChat.rows.length > 0) {
                finalChatId = existingChat.rows[0].id;
                console.log('✅ Найден существующий приватный чат с ID:', finalChatId);
            } else {
                console.log('⚠️ Приватный чат еще не создан, возвращаем пустой список');
                
                return res.json({
                    success: true,
                    messages: [],
                    pagination: {
                        currentPage: page,
                        totalPages: 0,
                        totalMessages: 0,
                        hasMore: false
                    }
                });
            }
        }
        
        if (!finalChatId) {
            return res.status(400).json({ 
                success: false, 
                error: 'chat_id или user_id обязателен',
                receivedParams: req.query 
            });
        }
        
        if (finalChatId) {
            const chatCheck = await pool.query(
                'SELECT id FROM chats WHERE id = $1',
                [finalChatId]
            );
            
            if (chatCheck.rows.length === 0) {
                return res.status(404).json({ 
                    success: false, 
                    error: 'Чат не найден' 
                });
            }
        }
        
        const accessCheck = await pool.query(
            'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
            [finalChatId, userId]
        );
        
        if (accessCheck.rows.length === 0) {
            return res.status(403).json({ 
                success: false, 
                error: 'Нет доступа к этому чату' 
            });
        }
        
        const result = await pool.query(`
            SELECT 
                m.id, 
                m.user_id, 
                m.text, 
                m.type_id, 
                m.file_url, 
                m.created_at,
                m.duration,
                m.is_forwarded,
                m.forwarded_from,
                m.is_pinned,
                mt.name as type_name,
                u.name as user_name,
                u.nickname as user_nickname,
                u.avatar_url as user_avatar_url
            FROM messages m
            JOIN message_types mt ON m.type_id = mt.id
            LEFT JOIN users u ON m.user_id = u.id
            WHERE m.chat_id = $1
            ORDER BY m.created_at DESC
            LIMIT $2 OFFSET $3
        `, [finalChatId, limit, offset]);
        
        const countResult = await pool.query(
            'SELECT COUNT(*) FROM messages WHERE chat_id = $1',
            [finalChatId]
        );
        
        const totalCount = parseInt(countResult.rows[0].count);
        
        const messages = result.rows.map(msg => {
            const decryptedText = msg.text ? decryptMessage(msg.text) : '';
            
            const decryptedName = msg.user_name ? decryptString(msg.user_name) : null;
            const decryptedNickname = msg.user_nickname ? decryptString(msg.user_nickname) : null;
            
            let displayName = 'Unknown User';
            if (decryptedNickname && decryptedNickname.trim()) {
                displayName = decryptedNickname.trim();
            } else if (decryptedName && decryptedName.trim()) {
                displayName = decryptedName.trim();
            } else {
                displayName = `User ${msg.user_id}`;
            }
            
            return {
                id: msg.id,
                userId: msg.user_id,
                text: decryptedText,
                type: msg.type_name,
                typeId: msg.type_id,
                fileUrl: msg.file_url,
                createdAt: msg.created_at,
                duration: msg.duration,
                isForwarded: msg.is_forwarded || false,
                forwardedFrom: msg.forwarded_from || null,
                isPinned: msg.is_pinned || false,
                userName: decryptedName,
                userNickname: decryptedNickname,
                userAvatarUrl: msg.user_avatar_url,
                displayName: displayName
            };
        });
                
        res.json({
            success: true,
            messages: messages.reverse(),
            chat_id: finalChatId,
            pagination: {
                currentPage: page,
                totalPages: Math.ceil(totalCount / limit),
                totalMessages: totalCount,
                hasMore: page * limit < totalCount
            }
        });
    } catch (error) {
        console.error('Chat messages error:', error);
        res.status(500).json({ 
            success: false, 
            error: 'Ошибка получения сообщений',
            details: error.message 
        });
    }
});

// 12. POST Отправка сообщения
app.post('/api/send-message', authMiddleware, async (req, res) => {
    const { text, user_id, chat_id } = req.body;
    let type_id = req.body.type_id || 1;
    
    if (!text || text.trim() === '') {
        return res.status(400).json({ error: 'Введите текст сообщения' });
    }

    try {
        const userId = req.user.userId;
        const cleanText = text.trim();
        
        console.log('📨 Отправка сообщения:', {
            userId,
            textPreview: cleanText.substring(0, 100),
            textLength: cleanText.length,
            user_id,
            chat_id,
            type_id
        });
        
        const currentUserCheck = await pool.query(
            'SELECT id FROM users WHERE id = $1',
            [userId]
        );
        
        if (currentUserCheck.rows.length === 0) {
            return res.status(400).json({ error: 'Текущий пользователь не найден' });
        }

        const encryptedText = encryptMessage(cleanText);

        let finalChatId = chat_id;
        let recipientId = user_id;

        console.log('🔍 Определение чата:', {
            finalChatId,
            recipientId,
            userId
        });

        if (!finalChatId && recipientId) {
            console.log('🔍 Поиск существующего приватного чата...');
            
            const recipientCheck = await pool.query(
                'SELECT id, email_encrypted FROM users WHERE id = $1',
                [recipientId]
            );
            
            if (recipientCheck.rows.length === 0) {
                return res.status(400).json({ error: 'Получатель не найден' });
            }

            const existingChat = await pool.query(`
                SELECT c.id FROM chats c
                JOIN chat_participants cp1 ON c.id = cp1.chat_id
                JOIN chat_participants cp2 ON c.id = cp2.chat_id
                WHERE cp1.user_id = $1 
                  AND cp2.user_id = $2 
                  AND c.is_private = true
                LIMIT 1
            `, [userId, recipientId]);

            if (existingChat.rows.length > 0) {
                finalChatId = existingChat.rows[0].id;
                console.log('✅ Найден существующий чат:', finalChatId);
            } else {
                console.log('🔍 Создание нового приватного чата...');
                
                const recipient = recipientCheck.rows[0];
                let chatTitle = 'Личный чат';
                
                if (recipient.email_encrypted) {
                    const decryptedEmail = decryptString(recipient.email_encrypted);
                    chatTitle = `Личный чат с ${decryptedEmail || 'пользователем'}`;
                }
                
                console.log('📝 Создание чата с названием:', chatTitle);
                
                const chatResult = await pool.query(
                    'INSERT INTO chats (title, is_private, created_at) VALUES ($1, true, NOW()) RETURNING id',
                    [chatTitle]
                );
                
                finalChatId = chatResult.rows[0].id;
                console.log('✅ Создан новый чат с ID:', finalChatId);

                try {
                    await pool.query(
                        'INSERT INTO chat_participants (chat_id, user_id, joined_at) VALUES ($1, $2, NOW()), ($1, $3, NOW())',
                        [finalChatId, userId, recipientId]
                    );
                    
                    console.log('✅ Добавлены участники чата');
                } catch (insertError) {
                    console.error('❌ Ошибка добавления участников:', insertError.message);
                    
                    await pool.query('DELETE FROM chats WHERE id = $1', [finalChatId]);
                    
                    return res.status(500).json({ 
                        error: 'Ошибка создания чата', 
                        details: 'Не удалось добавить участников в чат' 
                    });
                }
            }
        } else if (finalChatId) {
            const chatAccessCheck = await pool.query(
                'SELECT 1 FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
                [finalChatId, userId]
            );
            
            if (chatAccessCheck.rows.length === 0) {
                return res.status(403).json({ error: 'Вы не участник этого чата' });
            }
        }

        if (!finalChatId) {
            finalChatId = 1;
            console.log('📝 Используется общий чат (ID=1)');
        }

        console.log('✅ Финальный chat_id:', finalChatId);

        const typeCheck = await pool.query(
            'SELECT id FROM message_types WHERE id = $1',
            [type_id]
        );
        
        if (typeCheck.rows.length === 0) {
            console.log('⚠️ Тип сообщения не найден, используем тип 1 (text)');
            type_id = 1;
        }

        const insertResult = await pool.query(
            `INSERT INTO messages (user_id, text, type_id, chat_id, created_at) 
            VALUES ($1, $2, $3, $4, NOW()) 
            RETURNING id, created_at`,
            [userId, encryptedText, type_id, finalChatId]
        );

        const messageId = insertResult.rows[0].id;
        const createdAt = insertResult.rows[0].created_at;

        const decryptedTest = decryptMessage(encryptedText);
        console.log('✅ Сообщение сохранено:', {
            messageId,
            chatId: finalChatId,
            originalLength: cleanText.length,
            encryptedLength: encryptedText.length,
            decryptionMatch: cleanText === decryptedTest
        });

        res.json({ 
            success: true, 
            message_id: messageId, 
            created_at: createdAt,
            chat_id: finalChatId
        });
        
    } catch (error) {
        console.error('❌ Send message error:', error);
        
        let errorMessage = 'Ошибка отправки сообщения';
        let errorDetails = error.message;
        
        if (error.message.includes('foreign key constraint')) {
            if (error.message.includes('chat_participants_user_id_fkey')) {
                errorMessage = 'Один из пользователей не существует';
                errorDetails = 'Проверьте, что отправитель и получатель зарегистрированы в системе';
            } else if (error.message.includes('messages_chat_id_fkey')) {
                errorMessage = 'Чат не существует';
                errorDetails = 'Указанный чат не найден в системе';
            }
        }
        
        res.status(500).json({ 
            error: errorMessage,
            details: errorDetails 
        });
    }
});

// 13. POST Закрепление сообщения в чате
app.post('/api/chats/:chatId/pinned-messages', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const { message_id } = req.body;
  const userId = req.user.userId;

  try {
    const chatCheck = await pool.query(
      `SELECT * FROM chat_participants 
       WHERE chat_id = $1 AND user_id = $2`,
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не являетесь участником этого чата' 
      });
    }

    const updateQuery = `
      UPDATE messages 
      SET is_pinned = true 
      WHERE id = $1 AND chat_id = $2
      RETURNING *
    `;
    
    const result = await pool.query(updateQuery, [message_id, chatId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    res.json({ success: true, message: result.rows[0] });
  } catch (error) {
    console.error('Ошибка закрепления сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 14. DELETE Открепление сообщения в чате
app.delete('/api/chats/:chatId/pinned-messages/:messageId', authMiddleware, async (req, res) => {
  const { chatId, messageId } = req.params;
  const userId = req.user.userId;

  try {
    const chatCheck = await pool.query(
      `SELECT * FROM chat_participants 
       WHERE chat_id = $1 AND user_id = $2`,
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не являетесь участником этого чата' 
      });
    }

    const updateQuery = `
      UPDATE messages 
      SET is_pinned = false 
      WHERE id = $1 AND chat_id = $2
      RETURNING *
    `;
    
    const result = await pool.query(updateQuery, [messageId, chatId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    res.json({ success: true, message: result.rows[0] });
  } catch (error) {
    console.error('Ошибка открепления сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 15. GET Получение закрепленных сообщений чата (ИСПРАВЛЕННЫЙ)
app.get('/api/chats/:chatId/pinned-messages', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const userId = req.user.userId;

  try {
    const chatCheck = await pool.query(
      `SELECT * FROM chat_participants 
       WHERE chat_id = $1 AND user_id = $2`,
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не являетесь участником этого чата' 
      });
    }

    const checkUpdatedAt = await pool.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'messages' 
        AND column_name = 'updated_at'
    `);

    const hasUpdatedAt = checkUpdatedAt.rows.length > 0;
    const updatedAtField = hasUpdatedAt ? 'm.updated_at,' : '';
    
    const query = `
      SELECT 
        m.id,
        m.user_id,
        m.chat_id,
        m.text,
        m.type_id,
        m.file_url,
        m.duration,
        m.is_forwarded,
        m.forwarded_from,
        m.is_pinned,
        m.created_at,
        ${updatedAtField}
        u.name,
        u.nickname,
        u.avatar_url
      FROM messages m
      LEFT JOIN users u ON m.user_id = u.id
      WHERE m.chat_id = $1 AND m.is_pinned = true
      ORDER BY m.created_at DESC
    `;
    
    const result = await pool.query(query, [chatId]);
    
    const createDisplayName = (user) => {
      const decryptedName = user.name ? decryptString(user.name) : null;
      const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
      
      if (decryptedNickname && decryptedNickname.trim()) {
        return decryptedNickname.trim();
      }
      
      if (decryptedName && decryptedName.trim()) {
        return decryptedName.trim();
      }
      
      return `User ${user.user_id}`;
    };
    
    const formattedMessages = result.rows.map(msg => {
      const userData = {
        nickname: msg.nickname,
        name: msg.name,
        user_id: msg.user_id
      };
      
      const decryptedText = decryptMessage(msg.text);
      
      const message = {
        id: msg.id,
        userId: msg.user_id,
        chatId: msg.chat_id,
        text: decryptedText,
        typeId: msg.type_id,
        fileUrl: msg.file_url,
        duration: msg.duration,
        isForwarded: msg.is_forwarded,
        forwardedFrom: msg.forwarded_from,
        isPinned: msg.is_pinned,
        createdAt: msg.created_at,
        userName: msg.name ? decryptString(msg.name) : null,
        userNickname: msg.nickname ? decryptString(msg.nickname) : null,
        userAvatarUrl: msg.avatar_url,
        displayName: createDisplayName(userData)
      };
      
      if (msg.updated_at) {
        message.updatedAt = msg.updated_at;
      }
      
      return message;
    });
    
    res.json({ 
      success: true, 
      pinned_messages: formattedMessages 
    });
  } catch (error) {
    console.error('Ошибка получения закрепленных сообщений:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 16. POST Загрузка файлов - УНИВЕРСАЛЬНАЯ ВЕРСИЯ
app.post('/api/upload', authMiddleware, uploadChat.any(), async (req, res) => {
    try {
        console.log('📤 Upload request received:', {
            files: req.files?.map(f => ({
                fieldname: f.fieldname,
                originalname: f.originalname,
                mimetype: f.mimetype,
                size: f.size
            })),
            body: req.body
        });

        const files = [];
        
        if (req.file) {
            files.push(req.file);
        }
        
        if (req.files && Array.isArray(req.files)) {
            files.push(...req.files);
        }

        if (files.length === 0) {
            return res.status(400).json({ 
                success: false,
                error: 'Файлы не получены сервером' 
            });
        }

        console.log(`📦 Обработка ${files.length} файлов`);
        
        const results = [];
        const errors = [];
        
        for (const file of files) {
            try {
                const { originalname, mimetype, size, buffer } = file;
                const userId = req.user.userId;
                const { chat_id, text } = req.body;

                const typeId = getFileTypeId(mimetype, originalname);
                
                const typeResult = await pool.query(
                    'SELECT name FROM message_types WHERE id = $1',
                    [typeId]
                );
                const typeName = typeResult.rows[0]?.name || 'file';

                console.log(`📄 Файл: ${originalname}, тип: ${typeName} (ID: ${typeId})`);
                
                let s3Url;
                try {
                    s3Url = await uploadToS3(buffer, originalname, mimetype);
                    console.log(`✅ Файл загружен в S3: ${s3Url}`);
                } catch (s3Error) {
                    console.error('❌ S3 upload failed:', s3Error);
                    errors.push({
                        file: originalname,
                        error: 'Ошибка загрузки в S3',
                        details: s3Error.message
                    });
                    continue;
                }
                
                const fileHash = crypto.randomBytes(16).toString('hex');
                const chatId = chat_id || 1;

                let messageText = '';
                if (text && text.trim()) {
                    messageText = encryptMessage(text.trim());
                } else {
                    try {
                        const decodedName = Buffer.from(originalname, 'binary').toString('utf8');
                        messageText = `Файл: ${decodedName}`;
                    } catch (error) {
                        messageText = `Файл: ${originalname}`;
                    }
                }

                const insertResult = await pool.query(`
                    INSERT INTO messages (user_id, text, type_id, file_url, file_hash, file_size, chat_id, created_at) 
                    VALUES ($1, $2, $3, $4, $5, $6, $7, NOW()) 
                    RETURNING id, created_at
                `, [userId, messageText, typeId, s3Url, fileHash, size, chatId]);

                results.push({
                    success: true,
                    file_url: s3Url,
                    file_name: fileHash,
                    original_name: originalname,
                    file_type: typeName,
                    file_size: size,
                    message_id: insertResult.rows[0].id,
                    created_at: insertResult.rows[0].created_at,
                    type_id: typeId
                });

                console.log(`✅ Файл обработан: ${originalname} (${typeName})`);

            } catch (fileError) {
                console.error(`❌ Ошибка обработки файла:`, fileError);
                errors.push({
                    file: file.originalname,
                    error: fileError.message
                });
            }
        }

        if (results.length === 0) {
            return res.status(500).json({
                success: false,
                error: 'Не удалось обработать ни один файл',
                errors: errors
            });
        } else if (results.length === 1 && errors.length === 0) {
            return res.json(results[0]);
        } else {
            return res.json({
                success: true,
                results: results,
                errors: errors.length > 0 ? errors : undefined
            });
        }

    } catch (error) {
        console.error('❌ Upload error:', error);
        res.status(500).json({
            success: false,
            error: 'Внутренняя ошибка сервера',
            details: error.message
        });
    }
});

// 17. GET Дебаг эндпоинт
app.get('/api/debug/uploads', async (req, res) => {
    try {
        const uploadDir = path.join(__dirname, 'uploads');
        
        if (!fs.existsSync(uploadDir)) {
            return res.json({
                exists: false,
                message: 'Upload directory does not exist'
            });
        }
        
        const files = fs.readdirSync(uploadDir);
        const fileInfo = await Promise.all(
            files.map(async (file) => {
                const filePath = path.join(uploadDir, file);
                const stats = await fs.promises.stat(filePath);
                return {
                    name: file,
                    size: stats.size,
                    modified: stats.mtime,
                    url: `${BASE_URL}/uploads/${file}`,
                    path: `/uploads/${file}`
                };
            })
        );
        
        res.json({
            exists: true,
            total_files: files.length,
            files: fileInfo
        });
    } catch (error) {
        res.status(500).json({ 
            error: 'Ошибка чтения директории',
            details: error.message
        });
    }
});

// 18. GET Получение всех пользователей
app.get('/api/users', authMiddleware, async (req, res) => {
    try {
        const result = await pool.query(
            'SELECT id, email_encrypted, name, nickname, created_at FROM users ORDER BY id'
        );
        
        const users = result.rows.map(user => ({
            id: user.id,
            email: decryptString(user.email_encrypted),
            name: user.name ? decryptString(user.name) : null,
            nickname: user.nickname ? decryptString(user.nickname) : null,
            created_at: user.created_at
        }));
        
        res.json({
            success: true,
            users
        });
    } catch (error) {
        console.error('Get users error:', error);
        res.status(500).json({ error: 'Ошибка получения пользователей' });
    }
});

// 19. GET Получить профиль пользователя (текущего или по ID)
app.get('/api/user', authMiddleware, async (req, res) => {
  try {
    console.log('🔍 GET /api/user called by user:', req.user.userId, 'Query:', req.query);
    let userId = req.query.id ? parseInt(req.query.id) : req.user.userId;
    
    if (!userId || isNaN(userId)) {
      return res.status(400).json({ error: 'Неверный ID пользователя' });
    }
    
    const { rows } = await pool.query(
      'SELECT id, email_encrypted, name, nickname, birthday, gender, avatar_url, avatar_color, is_verified, created_at FROM users WHERE id = $1',
      [userId]
    );
    
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    
    const user = rows[0];
    const isCurrentUser = userId === req.user.userId;
    
    let decryptedName = null;
    let decryptedNickname = null;
    try {
      if (user.name) {
        decryptedName = decryptString(user.name);
      }
      if (user.nickname) {
        decryptedNickname = decryptString(user.nickname);
      }
    } catch (decryptError) {
      console.error('Name/Nickname decryption error:', decryptError);
    }
    
    let decryptedEmail = '';
    if (isCurrentUser) {
      try {
        if (user.email_encrypted) {
          decryptedEmail = decryptString(user.email_encrypted);
        }
      } catch (decryptError) {
        console.error('Email decryption error:', decryptError);
        decryptedEmail = '';
      }
    }
    
    let birthdayFormatted = null;
    if (user.birthday) {
      try {
        const date = new Date(user.birthday);
        birthdayFormatted = date.toISOString().split('T')[0];
      } catch (dateError) {
        console.error('Date formatting error:', dateError);
        birthdayFormatted = user.birthday;
      }
    }
    
    const userResponse = {
      id: user.id,
      name: decryptedName,
      nickname: decryptedNickname || '',
      birthday: birthdayFormatted,
      gender: user.gender || null,
      photo_url: user.avatar_url,
      avatar_url: user.avatar_url,
      avatar_color: user.avatar_color || null,
      is_verified: user.is_verified || false,
      created_at: user.created_at
    };
    
    if (isCurrentUser && decryptedEmail) {
      userResponse.email = decryptedEmail;
    }
    
    console.log('✅ GET /api/user response:', userResponse);
    res.json(userResponse);
    
  } catch (error) {
    console.error('GET /api/user error:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// 19.1 Обновить профиль пользователя 
app.put('/api/user', authMiddleware, uploadAvatar.single('avatar'), async (req, res) => {
  try {
    console.log('📝 PUT /api/user called by user:', req.user.userId);
    console.log('📋 Request body:', req.body);
    console.log('📁 Request file:', req.file ? 'avatar uploaded' : 'no avatar');
    
    const userId = req.user.userId;
    const { name, nickname, birthday, gender } = req.body;
    
    console.log('👤 Update profile request:', {
      userId,
      hasFile: !!req.file,
      name,
      nickname,
      birthday,
      gender
    });
    
    const trimmedName = name ? name.trim() : '';
    const trimmedNickname = nickname ? nickname.trim() : '';
    
    if (!trimmedName && !trimmedNickname) {
      return res.status(400).json({ error: 'Заполните хотя бы одно поле: имя или никнейм' });
    }

    if (trimmedNickname) {
      const { rows: allUsers } = await pool.query(
        'SELECT id, nickname FROM users WHERE nickname IS NOT NULL'
      );
      
      const nicknameExists = allUsers.some(user => {
        if (user.id === userId) return false;
        if (!user.nickname) return false;
        try {
          const decrypted = decryptString(user.nickname);
          return decrypted === trimmedNickname;
        } catch (e) {
          return false;
        }
      });
      
      if (nicknameExists) {
        return res.status(409).json({ error: 'Никнейм уже занят', taken: true });
      }
    }

    let encryptedName = null;
    if (trimmedName) {
      encryptedName = encryptString(trimmedName);
    }
    
    let encryptedNickname = null;
    if (trimmedNickname) {
      encryptedNickname = encryptString(trimmedNickname);
    }
    
    let avatarUrl = null;
    if (req.file) {
      try {
        const buffer = req.file.buffer;
        
        if (buffer.length < 100) {
          console.error('❌ Buffer too small:', buffer.length);
          return res.status(400).json({ error: 'Изображение слишком маленькое' });
        }
        
        avatarUrl = await uploadToS3Avatar(buffer);
        
      } catch (error) {
        console.error('🚨 Avatar upload failed:', error.message);
        return res.status(400).json({ 
          error: 'Ошибка загрузки аватара',
          details: error.message 
        });
      }
    }

    const updateFields = [];
    const queryParams = [];
    let paramIndex = 1;
    
    if (encryptedName) {
      updateFields.push(`name = $${paramIndex++}`);
      queryParams.push(encryptedName);
    }
    
    if (encryptedNickname) {
      updateFields.push(`nickname = $${paramIndex++}`);
      queryParams.push(encryptedNickname);
    } else {
      updateFields.push(`nickname = NULL`);
    }
    
    if (birthday !== undefined) {
      updateFields.push(`birthday = $${paramIndex++}`);
      queryParams.push(birthday || null);
    }
    
    if (gender !== undefined) {
      updateFields.push(`gender = $${paramIndex++}`);
      queryParams.push(gender || null);
    }
    
    if (avatarUrl) {
      updateFields.push(`avatar_url = $${paramIndex++}`);
      queryParams.push(avatarUrl);
    }
    
    queryParams.push(userId);
    
    const query = `
      UPDATE users 
      SET ${updateFields.join(', ')}
      WHERE id = $${paramIndex}
      RETURNING id, email_encrypted, name, nickname, birthday, gender, avatar_url`;

    const { rows } = await pool.query(query, queryParams);
    
    const decryptedEmail = decryptString(rows[0].email_encrypted);
    const decryptedName = rows[0].name ? decryptString(rows[0].name) : null;
    const decryptedNickname = rows[0].nickname ? decryptString(rows[0].nickname) : null;
    
    let birthdayFormatted = null;
    if (rows[0].birthday) {
      try {
        const date = new Date(rows[0].birthday);
        birthdayFormatted = date.toISOString().split('T')[0];
      } catch (e) {
        birthdayFormatted = rows[0].birthday;
      }
    }

    const response = { 
      success: true, 
      user: {
        id: rows[0].id,
        email: decryptedEmail,
        name: decryptedName,
        nickname: decryptedNickname,
        birthday: birthdayFormatted,
        gender: rows[0].gender,
        avatar_url: rows[0].avatar_url || null
      }
    };
    
    console.log('✅ PUT /api/user response:', response);
    res.json(response);
    
  } catch (error) {
    console.error('🚨 ERROR:', error);
    res.status(500).json({ 
      error: 'Ошибка сервера',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 19.2 ПРОВЕРКА ДОСТУПНОСТИ НИКНЕЙМА 
app.post('/api/user/check-nickname', authMiddleware, async (req, res) => {
  try {
    console.log('🔍 POST /api/user/check-nickname called:', req.body);
    const { nickname } = req.body;
    
    if (!nickname || nickname.trim().length === 0) {
      return res.json({ available: false, error: 'Никнейм не может быть пустым' });
    }
    
    const cleanNickname = nickname.trim();
    
    const { rows } = await pool.query(
      'SELECT id, nickname FROM users WHERE nickname IS NOT NULL'
    );
    
    const isTaken = rows.some(user => {
      if (user.id === req.user.userId) return false;
      if (!user.nickname) return false;
      try {
        const decrypted = decryptString(user.nickname);
        return decrypted === cleanNickname;
      } catch (e) {
        return false;
      }
    });
    
    const response = { 
      available: !isTaken,
      taken: isTaken,
      message: isTaken ? 'Никнейм уже занят' : 'Никнейм свободен'
    };
    
    console.log('✅ POST /api/user/check-nickname response:', response);
    res.json(response);
    
  } catch (error) {
    console.error('Ошибка проверки никнейма:', error);
    res.status(500).json({ available: false, error: 'Ошибка сервера' });
  }
});

// 20. GET Тестовый эндпоинт
app.get('/api/test', (req, res) => {
    res.json({
        success: true,
        message: 'API работает!',
        server: 'SaferChat Local Development',
        time: new Date().toISOString(),
        endpoints: [
            'POST /api/send-verification-code - Отправить код подтверждения на email',
            'POST /api/verify-email-code   - Проверить код подтверждения email',
            'POST /api/register            - Регистрация (требует код подтверждения)',
            'POST /api/login               - Вход',
            'POST /api/reset-password      - Сброс пароля (отправка 4-значного кода)',
            'POST /api/verify-reset-code   - Проверить код сброса пароля',
            'POST /api/confirm-reset       - Установить новый пароль'
        ]
    });
});

// Получение медиафайлов чата
app.get('/api/chats/:chatId/media', authMiddleware, async (req, res) => {
  const { chatId } = req.params;
  const userId = req.user.userId;

  try {
    const chatCheck = await pool.query(
      'SELECT * FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не участник этого чата' 
      });
    }

    const photosQuery = `
      SELECT id, file_url, created_at, 
             substring(file_url from '[^/]*$') as file_name
      FROM messages
      WHERE chat_id = $1 
        AND type_id = 2 
        AND file_url ~* '\\.(jpg|jpeg|png|gif|bmp|webp)$'
      ORDER BY created_at DESC
    `;
    const photos = await pool.query(photosQuery, [chatId]);

    const videosQuery = `
      SELECT id, file_url, created_at,
             substring(file_url from '[^/]*$') as file_name
      FROM messages
      WHERE chat_id = $1 
        AND type_id = 2 
        AND file_url ~* '\\.(mp4|avi|mov|wmv|flv|webm)$'
      ORDER BY created_at DESC
    `;
    const videos = await pool.query(videosQuery, [chatId]);

    const audiosQuery = `
      SELECT id, file_url, created_at, duration,
             substring(file_url from '[^/]*$') as file_name
      FROM messages
      WHERE chat_id = $1 
        AND (type_id = 4 OR file_url ~* '\\.(mp3|wav|m4a|aac|ogg)$')
      ORDER BY created_at DESC
    `;
    const audios = await pool.query(audiosQuery, [chatId]);

    res.json({
      success: true,
      photos: photos.rows,
      videos: videos.rows,
      audios: audios.rows,
    });
  } catch (error) {
    console.error('Ошибка получения медиа:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 21. GET Получение статуса кода подтверждения
app.get('/api/verification-status/:email', async (req, res) => {
    const { email } = req.params;
    
    try {
        const mapKey = getMapKey(email);
        const verificationData = verificationCodes.get(mapKey);
        
        if (!verificationData) {
            return res.json({
                exists: false,
                verified: false,
                expiresAt: null
            });
        }
        
        res.json({
            exists: true,
            verified: verificationData.verified || false,
            expiresAt: verificationData.expiresAt,
            expiresIn: Math.max(0, Math.floor((verificationData.expiresAt - Date.now()) / 1000)),
            attempts: verificationData.attempts
        });
        
    } catch (error) {
        console.error('Get verification status error:', error);
        res.status(500).json({ error: 'Ошибка получения статуса' });
    }
});

// 22. POST Отправка обращения в поддержку
app.post('/api/support-ticket', authMiddleware, async (req, res) => {
    const { name, message } = req.body;
    const userId = req.user.userId;

    if (!name || !name.trim()) {
        return res.status(400).json({ 
            success: false, 
            error: 'Укажите ваше имя' 
        });
    }

    if (!message || !message.trim()) {
        return res.status(400).json({ 
            success: false, 
            error: 'Введите описание проблемы' 
        });
    }

    if (message.trim().length === 0) {
        return res.status(400).json({ 
            success: false, 
            error: 'Сообщение не может быть пустым' 
        });
    }

    try {
        const userResult = await pool.query(
            'SELECT email_encrypted FROM users WHERE id = $1',
            [userId]
        );
        
        if (userResult.rows.length === 0) {
            return res.status(404).json({ 
                success: false, 
                error: 'Пользователь не найден' 
            });
        }
        
        const userEmail = decryptString(userResult.rows[0].email_encrypted);
        
        console.log('📧 Support ticket:', { userId, userEmail, hasEmail: !!userEmail });

        const date = new Date();
        const year = date.getFullYear().toString().slice(-2);
        const month = (date.getMonth() + 1).toString().padStart(2, '0');
        const day = date.getDate().toString().padStart(2, '0');
        const randomNum = Math.floor(1000 + Math.random() * 9000);
        const ticketNumber = `ST-${year}${month}${day}-${randomNum}`;

        const messageHash = crypto.createHash('sha256').update(message.trim()).digest('hex');
        const originalMessageLength = message.trim().length;
        
        const timestamp = Date.now();
        const storedData = `HASH:${messageHash}|LEN:${originalMessageLength}|TS:${timestamp}`;

        const insertResult = await pool.query(
            `INSERT INTO support_tickets (
                ticket_number, 
                user_email, 
                user_name, 
                user_message, 
                created_at
            ) VALUES ($1, $2, $3, $4, NOW()) 
            RETURNING id, ticket_number, created_at`,
            [ticketNumber, userEmail, name.trim(), storedData]
        );

        const ticket = insertResult.rows[0];
        const formattedDate = new Date(ticket.created_at).toLocaleString('ru-RU');

        try {
            const mailOptions = {
                from: `"Safer Chat Support" <${EMAIL_USER}>`,
                to: 'support@saferchat.me',
                subject: `[Поддержкa SaferChat] Обращение #${ticketNumber}`,
                text: `
НОВОЕ ОБРАЩЕНИЕ В ПОДДЕРЖКУ

Номер обращения: ${ticketNumber}
Дата создания: ${formattedDate}

ДАННЫЕ ПОЛЬЗОВАТЕЛЯ:
Имя: ${name.trim()}
Email: ${userEmail}
ID пользователя: ${userId}

СООБЩЕНИЕ:
${message.trim()}

---
Это автоматическое уведомление о новом обращении в поддержку SaferChat.
                `,
                html: `
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px 10px 0 0; text-align: center; }
        .content { background: #f9f9f9; padding: 20px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 10px 10px; }
        .ticket-info { background: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid #4CAF50; }
        .user-info { background: #e3f2fd; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .message-box { background: white; padding: 20px; border-radius: 8px; border: 1px solid #ddd; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; color: #666; font-size: 12px; text-align: center; }
        .ticket-number { font-size: 24px; font-weight: bold; color: #4CAF50; margin: 10px 0; }
        .label { font-weight: bold; color: #555; }
        .value { color: #333; }
    </style>
</head>
<body>
    <div class="header">
        <h2>📨 НОВОЕ ОБРАЩЕНИЕ В ПОДДЕРЖКУ</h2>
    </div>
    
    <div class="content">
        <div class="ticket-info">
            <div class="ticket-number">№ ${ticketNumber}</div>
            <p><span class="label">Дата создания:</span> <span class="value">${formattedDate}</span></p>
        </div>
        
        <div class="user-info">
            <h3>👤 ДАННЫЕ ПОЛЬЗОВАТЕЛЯ</h3>
            <p><span class="label">Имя:</span> <span class="value">${name.trim()}</span></p>
            <p><span class="label">Email:</span> <span class="value">${userEmail}</span></p>
            <p><span class="label">ID пользователя:</span> <span class="value">${userId}</span></p>
        </div>
        
        <div class="message-box">
            <h3>📝 СООБЩЕНИЕ ПОЛЬЗОВАТЕЛЯ</h3>
            <p style="white-space: pre-wrap;">${message.trim()}</p>
        </div>
        
        <div class="footer">
            <p>© ${new Date().getFullYear()} Safer Chat. Все права защищены.</p>
        </div>
    </div>
</body>
</html>
                `
            };

            await transporter.sendMail(mailOptions);
            
            const userConfirmationMail = {
                from: `"Safer Chat Support" <${EMAIL_USER}>`,
                to: userEmail,
                subject: `Обращение в поддержку #${ticketNumber}`,
                text: `
Благодарим за обращение в поддержку SaferChat!

Номер вашего обращения: ${ticketNumber}
Дата обращения: ${formattedDate}

---
Ваша заявка принята в работу, мы ответим вам не позднее 24 часов с даты обращения.

---

С уважением,
Команда поддержки SaferChat
                `,
                html: `
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4CAF50; color: white; padding: 20px; border-radius: 8px; text-align: center; margin-bottom: 20px; }
        .content { background: white; padding: 20px; border-radius: 8px; border: 1px solid #e0e0e0; }
        .ticket-info { 
            background: #f5f5f5; 
            padding: 20px; 
            border-radius: 8px; 
            margin: 15px 0;
            border-left: 4px solid #4CAF50;
        }
        .info-item { 
            margin: 8px 0;
            font-size: 16px;
        }
        .label { 
            font-weight: bold; 
            color: #424242;
            min-width: 140px;
            display: inline-block;
        }
        .value { 
            color: #333;
        }
        .response-info { 
            background: #e8f5e9; 
            padding: 20px; 
            border-radius: 8px; 
            margin: 20px 0; 
            border: 1px solid #c8e6c9;
            text-align: center;
        }
        .footer { 
            margin-top: 25px; 
            padding-top: 15px; 
            border-top: 1px solid #eee; 
            color: #777; 
            font-size: 12px; 
            text-align: center; 
        }
        .highlight { 
            font-size: 16px; 
            font-weight: bold; 
            color: #2E7D32; 
            line-height: 1.5;
        }
    </style>
</head>
<body>
    <div class="header">
        <h2 style="margin: 0;">Благодарим за обращение!</h2>
    </div>
    
    <div class="content">
        <div class="ticket-info">
            <div class="info-item">
                <span class="label">Номер обращения:</span>
                <span class="value">${ticketNumber}</span>
            </div>
            <div class="info-item">
                <span class="label">Дата обращения:</span>
                <span class="value">${formattedDate}</span>
            </div>
        </div>
        
        <div class="response-info">
            <p class="highlight">Ваша заявка принята в работу, мы ответим вам не позднее 24 часов с даты обращения.</p>
        </div>
                
        <div class="footer">
            <p>С уважением,<br>Команда поддержки SaferChat</p>
            <p>По всем вопросам приложения: support@saferchat.me</p>
            <p>© ${new Date().getFullYear()} Safer Chat. Все права защищены.</p>
        </div>
    </div>
</body>
</html>
                `
            };

            await transporter.sendMail(userConfirmationMail);

        } catch (emailError) {
            console.error('❌ Ошибка отправки email:', emailError);
        }

        res.json({ 
            success: true, 
            message: 'Обращение успешно отправлено',
            ticketNumber: ticketNumber,
            ticketId: ticket.id,
            createdAt: ticket.created_at,
            confirmationSent: true,
            messageHash: messageHash
        });

    } catch (error) {
        console.error('Support ticket error:', error);
        
        if (error.code === '23505') {
            return res.status(400).json({ 
                success: false, 
                error: 'Обращение с таким номером уже существует' 
            });
        }
        
        if (error.code === '23503') {
            return res.status(400).json({ 
                success: false, 
                error: 'Пользователь не найден' 
            });
        }
        
        res.status(500).json({ 
            success: false, 
            error: 'Ошибка отправки обращения. Попробуйте позже.',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
});

// 23. GET Получение истории обращений пользователя 
app.get('/api/support-tickets', authMiddleware, async (req, res) => {
    try {
        const userId = req.user.userId;
        const userEmail = req.user.email;
        
        const result = await pool.query(
            `SELECT 
                id,
                ticket_number,
                user_name,
                user_message,
                status,
                priority,
                created_at,
                updated_at,
                resolved_at,
                resolution_notes
            FROM support_tickets 
            WHERE user_email = $1 
            ORDER BY created_at DESC 
            LIMIT 50`,
            [userEmail]
        );

        res.json({
            success: true,
            tickets: result.rows,
            total: result.rows.length
        });
        
    } catch (error) {
        console.error('Get support tickets error:', error);
        res.status(500).json({ 
            success: false, 
            error: 'Ошибка получения истории обращений' 
        });
    }
});

// 24. GET Проверка доступности S3 и аватаров
app.get('/api/debug/s3', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, email, avatar_url FROM users WHERE avatar_url IS NOT NULL LIMIT 10'
    );
    
    const s3Status = {
      endpoint: 'http://localhost:9000',
      bucket: 'safer-chat-media',
      users_with_avatars: rows.length,
      sample_avatars: rows.map(user => ({
        id: user.id,
        email: user.email,
        avatar_url: user.avatar_url
      }))
    };
    
    try {
      const testKey = `test-${Date.now()}.txt`;
      await s3Client.send(new PutObjectCommand({
        Bucket: 'safer-chat-media',
        Key: testKey,
        Body: 'test',
        ContentType: 'text/plain'
      }));
      s3Status.s3_write_test = 'success';
      
      await s3Client.send(new DeleteObjectCommand({
        Bucket: 'safer-chat-media',
        Key: testKey
      }));
      
    } catch (s3Error) {
      s3Status.s3_write_test = `failed: ${s3Error.message}`;
    }
    
    res.json(s3Status);
    
  } catch (error) {
    console.error('S3 debug error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 25. GET Тестовый эндпоинт для проверки S3 ссылок
app.get('/api/test-s3-url/:key', async (req, res) => {
  try {
    const { key } = req.params;
        
    try {
      const command = new GetObjectCommand({
        Bucket: 'safer-chat-media',
        Key: key,
      });
      
      const response = await s3Client.send(command);
      
      res.json({
        success: true,
        exists: true,
        contentType: response.ContentType,
        contentLength: response.ContentLength,
        lastModified: response.LastModified,
        url: `${BASE_URL}/s3-proxy/${key}`
      });
      
    } catch (s3Error) {
      if (s3Error.name === 'NoSuchKey') {
        res.json({
          success: false,
          exists: false,
          error: 'File not found in S3'
        });
      } else {
        throw s3Error;
      }
    }
    
  } catch (error) {
    console.error('❌ S3 URL test error:', error.message);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// 26. GET Тест S3 соединения
app.get('/api/debug/s3-test', async (req, res) => {
  try {
    
    const testKey = `test-connection-${Date.now()}.txt`;
    const testContent = 'S3 connection test';
    
    await s3Client.send(new PutObjectCommand({
      Bucket: 'safer-chat-media',
      Key: testKey,
      Body: testContent,
      ContentType: 'text/plain',
      ACL: 'public-read'
    }));
        
    const testUrl = `${BASE_URL}/s3-proxy/${testKey}`;
    
    const response = await fetch(testUrl);
    
    const result = {
      s3_write: 'success',
      s3_read: response.ok ? 'success' : 'failed',
      test_key: testKey,
      test_url: testUrl,
      proxy_status: response.status,
      bucket: 'safer-chat-media',
      endpoint: 'http://localhost:9000'
    };
    
    await s3Client.send(new DeleteObjectCommand({
      Bucket: 'safer-chat-media',
      Key: testKey
    }));
    
    res.json(result);
    
  } catch (error) {
    console.error('❌ S3 test failed:', error);
    res.status(500).json({ 
      error: 'S3 test failed',
      message: error.message,
      stack: error.stack 
    });
  }
});

// 27. GET Тест шифрования
app.get('/api/debug/encryption-test', (req, res) => {
    const testText = 'Тестовое сообщение для проверки шифрования ' + Date.now();
    const testName = 'Тестовое имя';
    const testNickname = 'test_nick';
    
    
    const encryptedText = encryptMessage(testText);
    const decryptedText = decryptMessage(encryptedText);
    
    const encryptedName = encryptString(testName);
    const decryptedName = decryptString(encryptedName);
    
    const encryptedNickname = encryptString(testNickname);
    const decryptedNickname = decryptString(encryptedNickname);
    
    res.json({
        success: true,
        messages: {
            original: testText,
            encrypted: encryptedText,
            decrypted: decryptedText,
            match: testText === decryptedText
        },
        names: {
            original: testName,
            encrypted: encryptedName,
            decrypted: decryptedName,
            match: testName === decryptedName
        },
        nicknames: {
            original: testNickname,
            encrypted: encryptedNickname,
            decrypted: decryptedNickname,
            match: testNickname === decryptedNickname
        },
        encryptionKeyLength: ENCRYPTION_KEY.length,
        algorithm: 'aes-256-gcm'
    });
});

// 28. POST Восстановление старых сообщений (новый ключ не совпадает со старым)
app.post('/api/fix-old-messages', authMiddleware, async (req, res) => {
    try {        
        const result = await pool.query(`
            SELECT m.id, m.text, mt.name as type_name
            FROM messages m
            JOIN message_types mt ON m.type_id = mt.id
            WHERE mt.name = 'text'
            ORDER BY m.id DESC
            LIMIT 100
        `);
        
        let fixedCount = 0;
        const errors = [];
        
        for (const msg of result.rows) {
            console.log(`\n🔍 Сообщение ${msg.id}:`, {
                textPreview: msg.text?.substring(0, 30),
                type: msg.type_name
            });
            
            const decrypted = decryptMessage(msg.text);
            
            if (decrypted === '[Сообщение зашифровано другим ключом]') {
                console.log(`❌ Не удалось расшифровать сообщение ${msg.id}`);
                errors.push({
                    id: msg.id,
                    error: 'Cannot decrypt with current key'
                });
                
                await pool.query(
                    'UPDATE messages SET text = $1 WHERE id = $2',
                    ['[Сообщение не может быть расшифровано]', msg.id]
                );
                fixedCount++;
            }
        }
        
        res.json({
            success: true,
            fixed_count: fixedCount,
            errors: errors,
            message: `Обработано ${result.rows.length} сообщений, исправлено ${fixedCount}`
        });
        
    } catch (error) {
        console.error('Fix old messages error:', error);
        res.status(500).json({ 
            success: false,
            error: 'Ошибка исправления сообщений',
            details: error.message
        });
    }
});

// 29. GET Проверка совместимости ключей шифрования
app.get('/api/debug/encryption-compatibility', async (req, res) => {
    try {
        
        const result = await pool.query(`
            SELECT m.id, m.text, mt.name as type_name, m.created_at
            FROM messages m
            JOIN message_types mt ON m.type_id = mt.id
            WHERE m.text LIKE '%:%:%'
            ORDER BY m.created_at DESC
            LIMIT 5
        `);
        
        const compatibilityTests = await Promise.all(result.rows.map(async (msg) => {
            
            const decrypted = decryptMessage(msg.text);
            
            const isDecrypted = decrypted !== msg.text && decrypted !== '[Сообщение зашифровано другим ключом]';
            const isLikelyEncrypted = msg.text.includes(':') && msg.text.split(':').length === 3;
            
            console.log('   Удалось расшифровать:', isDecrypted ? '✅' : '❌');
            console.log('   Выглядит как зашифрованное:', isLikelyEncrypted ? '✅' : '❌');
            console.log('   Результат:', decrypted?.substring(0, 50) + '...');
            
            return {
                id: msg.id,
                type: msg.type_name,
                created_at: msg.created_at,
                is_encrypted: isLikelyEncrypted,
                can_decrypt: isDecrypted,
                result_preview: decrypted?.substring(0, 50),
                full_result: decrypted?.length > 100 ? decrypted?.substring(0, 100) + '...' : decrypted
            };
        }));
        
        const canDecryptCount = compatibilityTests.filter(t => t.can_decrypt).length;
        const encryptedCount = compatibilityTests.filter(t => t.is_encrypted).length;
        
        
        res.json({
            success: true,
            total_tested: compatibilityTests.length,
            encrypted_count: encryptedCount,
            can_decrypt_count: canDecryptCount,
            compatibility_rate: encryptedCount > 0 ? Math.round((canDecryptCount / encryptedCount) * 100) : 100,
            tests: compatibilityTests,
            current_key: ENCRYPTION_KEY.toString('hex'),
            key_length: ENCRYPTION_KEY.length,
            recommendation: canDecryptCount === 0 ? 
                '❌ Ключ не совместим со старыми сообщениями. Нужно использовать старый ключ или сбросить сообщения.' :
                '✅ Ключ совместим с частью сообщений.'
        });
        
    } catch (error) {
        console.error('Encryption compatibility check error:', error);
        res.status(500).json({ 
            success: false,
            error: 'Ошибка проверки совместимости',
            details: error.message
        });
    }
});

// 30. GET Создание нового фиксированного ключа
app.get('/api/debug/generate-new-key', (req, res) => {
    try {
        const newKey = crypto.randomBytes(32);
        const newKeyHex = newKey.toString('hex');
        
        res.json({
            success: true,
            new_key_hex: newKeyHex,
            key_length: newKey.length,
            instructions: 'Скопируйте этот ключ и замените значение ENCRYPTION_KEY в коде сервера'
        });
        
    } catch (error) {
        console.error('Generate new key error:', error);
        res.status(500).json({ 
            success: false,
            error: 'Ошибка генерации ключа',
            details: error.message
        });
    }
});

// Multer для загрузки аватаров каналов
const uploadChannels = multer({
  storage: multer.diskStorage({
    destination: function (req, file, cb) {
      const uploadDir = 'uploads/channels/';
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: function (req, file, cb) {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
      cb(null, 'channel-' + uniqueSuffix + path.extname(file.originalname));
    }
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: function (req, file, cb) {
    const allowedTypes = /jpeg|jpg|png|gif|webp/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (mimetype && extname) {
      return cb(null, true);
    } else {
      cb(new Error('Только изображения разрешены!'));
    }
  }
});

// 31. POST /api/channels - Создание канала
app.post('/api/channels', authMiddleware, uploadChannels.single('avatar'), async (req, res) => {
  const client = await pool.connect();
  
  try {
    const { name, description, avatar_color, selected_user_ids, channel_link } = req.body;
    const userId = req.user.userId;
        
    if (!name || name.trim().length === 0) {
      return res.status(400).json({ error: 'Название канала обязательно' });
    }
    
    if (name.trim().length > 100) {
      return res.status(400).json({ error: 'Название канала не должно превышать 100 символов' });
    }
    
    if (!channel_link || channel_link.trim().length === 0) {
      return res.status(400).json({ error: 'Ссылка канала обязательна' });
    }
    
    const cleanLink = channel_link.trim();
    
    const validLinkRegex = /^[a-zA-Z0-9_-]+$/;
    if (!validLinkRegex.test(cleanLink)) {
      return res.status(400).json({ 
        error: 'Ссылка может содержать только английские буквы, цифры, _ и -' 
      });
    }
    
    const linkCheck = await client.query(
      'SELECT id FROM channels WHERE channel_link = $1',
      [cleanLink]
    );
    
    if (linkCheck.rows.length > 0) {
      return res.status(400).json({ error: 'Эта ссылка уже занята' });
    }
    
    await client.query('BEGIN');
    
    let avatarUrl = null;
    if (req.file) {
      avatarUrl = `/uploads/channels/${req.file.filename}`;
    }
    
    const insertChannelQuery = `
      INSERT INTO channels (name, description, avatar_url, avatar_color, created_by, channel_link)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, name, description, avatar_url, avatar_color, created_by, channel_link, created_at
    `;
    
    const channelResult = await client.query(insertChannelQuery, [
      name.trim(),
      description ? description.trim() : null,
      avatarUrl,
      avatar_color || '#2196F3',
      userId,
      cleanLink
    ]);
    
    const channel = channelResult.rows[0];
    
    console.log(`✅ Канал ${channel.id} создан пользователем ${userId}`);
    
    await client.query(
      'INSERT INTO channel_members (channel_id, user_id, role) VALUES ($1, $2, $3)',
      [channel.id, userId, 'admin']
    );
    
    console.log(`✅ Пользователь ${userId} добавлен как admin канала ${channel.id}`);
    
    await client.query(
      'INSERT INTO channel_subscribers (channel_id, user_id, subscribed_at) VALUES ($1, $2, NOW())',
      [channel.id, userId]
    );
    
    console.log(`✅ Пользователь ${userId} автоматически подписан на канал ${channel.id}`);
    
    let selectedUserIdsArray = [];
    if (selected_user_ids) {
      try {
        selectedUserIdsArray = typeof selected_user_ids === 'string' 
          ? JSON.parse(selected_user_ids) 
          : selected_user_ids;
      } catch (e) {
        console.error('Ошибка парсинга selected_user_ids:', e);
      }
    }
    
    if (Array.isArray(selectedUserIdsArray) && selectedUserIdsArray.length > 0) {
      const memberInsertQuery = `
        INSERT INTO channel_members (channel_id, user_id, role)
        SELECT $1, id, 'member'
        FROM users
        WHERE id = ANY($2::int[])
        ON CONFLICT (channel_id, user_id) DO NOTHING
      `;
      
      await client.query(memberInsertQuery, [channel.id, selectedUserIdsArray]);
      
      const subscriberInsertQuery = `
        INSERT INTO channel_subscribers (channel_id, user_id, subscribed_at)
        SELECT $1, id, NOW()
        FROM users
        WHERE id = ANY($2::int[])
        ON CONFLICT (channel_id, user_id) DO NOTHING
      `;
      
      await client.query(subscriberInsertQuery, [channel.id, selectedUserIdsArray]);
      
      console.log(`✅ ${selectedUserIdsArray.length} пользователей добавлены и подписаны на канал ${channel.id}`);
    }
    
    const membersCountResult = await client.query(
      'SELECT COUNT(*) as count FROM channel_members WHERE channel_id = $1',
      [channel.id]
    );
    
    await client.query('COMMIT');
    
    console.log(`✅ Канал ${channel.id} успешно создан с ${membersCountResult.rows[0].count} участниками`);
    
    res.status(201).json({
      success: true,
      message: 'Канал успешно создан',
      channel: {
        ...channel,
        members_count: parseInt(membersCountResult.rows[0].count)
      }
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Ошибка создания канала:', error);
    
    if (req.file) {
      fs.unlink(req.file.path, (err) => {
        if (err) console.error('Ошибка удаления файла:', err);
      });
    }
    
    res.status(500).json({ 
      error: 'Ошибка создания канала',
      details: error.message 
    });
  } finally {
    client.release();
  }
});


// 32. GET /api/channels - Получение списка каналов пользователя
app.get('/api/channels', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    const query = `
      SELECT 
        c.id, 
        c.name, 
        c.description, 
        c.avatar_url, 
        c.avatar_color,
        c.created_by,
        c.created_at,
        cm.role,
        COUNT(DISTINCT cm2.user_id) as members_count
      FROM channels c
      INNER JOIN channel_members cm ON c.id = cm.channel_id
      LEFT JOIN channel_members cm2 ON c.id = cm2.channel_id
      WHERE cm.user_id = $1
      GROUP BY c.id, c.name, c.description, c.avatar_url, c.avatar_color, c.created_by, c.created_at, cm.role
      ORDER BY c.created_at DESC
    `;
    
    const result = await pool.query(query, [userId]);
    
    res.json({
      success: true,
      channels: result.rows
    });
    
  } catch (error) {
    console.error('Ошибка получения каналов:', error);
    res.status(500).json({ error: 'Ошибка получения списка каналов' });
  }
});

// 33. GET Получение информации о канале + счетчик подписчиков
app.get('/api/channels/:channelId', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const userId = req.user.userId;

  try {
    const channelQuery = `
      SELECT 
        c.*,
        COUNT(cs.id) as subscribers_count,
        EXISTS(
          SELECT 1 FROM channel_subscribers 
          WHERE channel_id = c.id AND user_id = $2
        ) as is_subscribed
      FROM channels c
      LEFT JOIN channel_subscribers cs ON c.id = cs.channel_id
      WHERE c.id = $1
      GROUP BY c.id
    `;
    
    const result = await pool.query(channelQuery, [channelId, userId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Канал не найден' });
    }
    
    res.json({ success: true, channel: result.rows[0] });
  } catch (error) {
    console.error('Ошибка получения информации о канале:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 34. Получение сообщений канала (с пагинацией) - ИСПРАВЛЕНО: шифрование текста
app.get('/api/channels/:channelId/messages', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const userId = req.user.userId;
  const page = parseInt(req.query.page) || 1;
  const limit = parseInt(req.query.limit) || 20;
  const offset = (page - 1) * limit;

  try {
    console.log(`📨 Запрос сообщений канала ${channelId} от пользователя ${userId}`);

    const accessCheck = await pool.query(`
      SELECT 
        c.id,
        c.created_by,
        CASE 
          WHEN c.created_by = $2 THEN true
          WHEN cs.user_id IS NOT NULL THEN true
          ELSE false
        END as has_access
      FROM channels c
      LEFT JOIN channel_subscribers cs ON cs.channel_id = c.id AND cs.user_id = $2
      WHERE c.id = $1
    `, [channelId, userId]);

    if (accessCheck.rows.length === 0) {
      console.log(`❌ Канал ${channelId} не найден`);
      return res.status(404).json({ 
        success: false, 
        error: 'Канал не найден' 
      });
    }

    if (!accessCheck.rows[0].has_access) {
      console.log(`⚠️ Пользователь ${userId} не имеет доступа к каналу ${channelId}`);
      return res.status(403).json({ 
        success: false, 
        error: 'Необходимо подписаться на канал для просмотра сообщений' 
      });
    }

    console.log(`✅ Доступ к каналу ${channelId} разрешен`);

    const messagesQuery = `
      SELECT 
        cm.id,
        cm.channel_id,
        cm.user_id,
        cm.text,
        cm.file_url,
        cm.type_id,
        cm.duration,
        cm.created_at,
        u.email_encrypted,
        u.nickname,
        u.name,
        u.avatar_url
      FROM channel_messages cm
      JOIN users u ON cm.user_id = u.id
      WHERE cm.channel_id = $1
      ORDER BY cm.created_at DESC
      LIMIT $2 OFFSET $3
    `;
    
    const result = await pool.query(messagesQuery, [channelId, limit, offset]);
    
    const messages = result.rows.map(msg => {
      const decryptedEmail = decryptString(msg.email_encrypted);
      const decryptedName = msg.name ? decryptString(msg.name) : null;
      const decryptedNickname = msg.nickname ? decryptString(msg.nickname) : null;
      const decryptedText = msg.text ? decryptMessage(msg.text) : '';
      
      const senderDisplayName = decryptedNickname || decryptedName || decryptedEmail || `User ${msg.user_id}`;
      
      return {
        id: msg.id,
        channel_id: msg.channel_id,
        user_id: msg.user_id,
        text: decryptedText,
        file_url: msg.file_url,
        type_id: msg.type_id,
        duration: msg.duration,
        created_at: msg.created_at,
        sender_email: decryptedEmail,
        sender_nickname: decryptedNickname,
        sender_name: decryptedName,
        sender_display_name: senderDisplayName,
        avatar_url: msg.avatar_url
      };
    }).reverse();

    console.log(`✅ Возвращено ${messages.length} сообщений из канала ${channelId}`);
    
    res.json({ 
      success: true, 
      messages: messages,
      page,
      limit
    });
  } catch (error) {
    console.error('❌ Ошибка загрузки сообщений канала:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера',
      details: error.message 
    });
  }
});


// 35. POST Отправка сообщения в канал - ИСПРАВЛЕНО: шифрование текста
app.post('/api/channels/:channelId/messages', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const { text, file_url, type_id = 1, duration } = req.body;
  const userId = req.user.userId;

  try {
    const channelCheck = await pool.query(
      'SELECT created_by FROM channels WHERE id = $1',
      [channelId]
    );

    if (channelCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Канал не найден' });
    }

    if (channelCheck.rows[0].created_by !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Только владелец канала может публиковать сообщения' 
      });
    }

    const encryptedText = text ? encryptMessage(text) : '';

    const insertQuery = `
      INSERT INTO channel_messages (channel_id, user_id, text, file_url, type_id, duration)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;
    
    const result = await pool.query(insertQuery, [
      channelId,
      userId,
      encryptedText,
      file_url || null,
      type_id,
      duration || null
    ]);
    
    const message = result.rows[0];
    message.text = text;
    
    res.json({ success: true, message: message });
  } catch (error) {
    console.error('Ошибка отправки сообщения в канал:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 36. DELETE Удаление поста (только автор)
app.delete('/api/channels/:channelId/messages/:messageId', authMiddleware, async (req, res) => {
  const { channelId, messageId } = req.params;
  const userId = req.user.userId;

  try {
    const checkQuery = `
      SELECT user_id FROM channel_messages 
      WHERE id = $1 AND channel_id = $2
    `;
    const checkResult = await pool.query(checkQuery, [messageId, channelId]);

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }

    if (checkResult.rows[0].user_id !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы можете удалять только свои сообщения' 
      });
    }

    await pool.query(
      'DELETE FROM channel_messages WHERE id = $1 AND channel_id = $2',
      [messageId, channelId]
    );
    
    res.json({ success: true, message: 'Сообщение удалено' });
  } catch (error) {
    console.error('Ошибка удаления сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 37. PUT Редактирование поста (только автор) - ИСПРАВЛЕНО: шифрование текста
app.put('/api/channels/:channelId/messages/:messageId', authMiddleware, async (req, res) => {
  const { channelId, messageId } = req.params;
  const { text } = req.body;
  const userId = req.user.userId;

  if (!text || text.trim() === '') {
    return res.status(400).json({ success: false, error: 'Текст не может быть пустым' });
  }

  try {
    const checkQuery = `
      SELECT user_id FROM channel_messages 
      WHERE id = $1 AND channel_id = $2
    `;
    const checkResult = await pool.query(checkQuery, [messageId, channelId]);

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }

    if (checkResult.rows[0].user_id !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы можете редактировать только свои сообщения' 
      });
    }

    const encryptedText = encryptMessage(text.trim());

    const updateQuery = `
      UPDATE channel_messages 
      SET text = $1, is_edited = true, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2 AND channel_id = $3
      RETURNING *
    `;
    
    const result = await pool.query(updateQuery, [encryptedText, messageId, channelId]);
    
    const message = result.rows[0];
    message.text = text;
    
    res.json({ success: true, message: message });
  } catch (error) {
    console.error('Ошибка редактирования сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 38. POST Закрепление поста
app.post('/api/channels/:channelId/pinned-messages', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const { message_id } = req.body;
  const userId = req.user.userId;

  try {
    const channelCheck = await pool.query(
      'SELECT created_by FROM channels WHERE id = $1',
      [channelId]
    );

    if (channelCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Канал не найден' });
    }

    if (channelCheck.rows[0].created_by !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Только владелец канала может закреплять сообщения' 
      });
    }

    const updateQuery = `
      UPDATE channel_messages 
      SET is_pinned = true 
      WHERE id = $1 AND channel_id = $2
      RETURNING *
    `;
    
    const result = await pool.query(updateQuery, [message_id, channelId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    const message = result.rows[0];
    if (message.text) {
      message.text = decryptMessage(message.text);
    }
    
    res.json({ success: true, message: message });
  } catch (error) {
    console.error('Ошибка закрепления сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 39. DELETE Открепление поста
app.delete('/api/channels/:channelId/pinned-messages/:messageId', authMiddleware, async (req, res) => {
  const { channelId, messageId } = req.params;
  const userId = req.user.userId;

  try {
    const channelCheck = await pool.query(
      'SELECT created_by FROM channels WHERE id = $1',
      [channelId]
    );

    if (channelCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Канал не найден' });
    }

    if (channelCheck.rows[0].created_by !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Только владелец канала может откреплять сообщения' 
      });
    }

    const updateQuery = `
      UPDATE channel_messages 
      SET is_pinned = false 
      WHERE id = $1 AND channel_id = $2
      RETURNING *
    `;
    
    const result = await pool.query(updateQuery, [messageId, channelId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Сообщение не найдено' });
    }
    
    const message = result.rows[0];
    if (message.text) {
      message.text = decryptMessage(message.text);
    }
    
    res.json({ success: true, message: message });
  } catch (error) {
    console.error('Ошибка открепления сообщения:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 40. GET Получение закрепленных сообщений - ИСПРАВЛЕНО: расшифровка текста
app.get('/api/channels/:channelId/pinned-messages', authMiddleware, async (req, res) => {
  const { channelId } = req.params;

  try {
    const query = `
      SELECT 
        cm.*,
        u.email_encrypted,
        u.nickname,
        u.name,
        u.avatar_url
      FROM channel_messages cm
      JOIN users u ON cm.user_id = u.id
      WHERE cm.channel_id = $1 AND cm.is_pinned = true
      ORDER BY cm.created_at DESC
    `;
    
    const result = await pool.query(query, [channelId]);
    
    const messages = result.rows.map(msg => {
      const decryptedName = msg.name ? decryptString(msg.name) : null;
      const decryptedNickname = msg.nickname ? decryptString(msg.nickname) : null;
      const decryptedEmail = msg.email_encrypted ? decryptString(msg.email_encrypted) : null;
      
      return {
        ...msg,
        text: msg.text ? decryptMessage(msg.text) : '',
        name: decryptedName,
        nickname: decryptedNickname,
        email: decryptedEmail,
        email_encrypted: undefined
      };
    });
    
    res.json({ success: true, pinned_messages: messages });
  } catch (error) {
    console.error('Ошибка получения закрепленных сообщений:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 41. POST Подписка на канал
app.post('/api/channels/:channelId/subscribe', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const userId = req.user.userId;

  try {
    const channelCheck = await pool.query('SELECT id FROM channels WHERE id = $1', [channelId]);
    
    if (channelCheck.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Канал не найден' });
    }

    const insertQuery = `
      INSERT INTO channel_subscribers (channel_id, user_id)
      VALUES ($1, $2)
      ON CONFLICT (channel_id, user_id) DO NOTHING
      RETURNING *
    `;
    
    const result = await pool.query(insertQuery, [channelId, userId]);
    
    if (result.rows.length > 0) {
      res.json({ success: true, message: 'Вы подписались на канал' });
    } else {
      res.json({ success: true, message: 'Вы уже подписаны на этот канал' });
    }
  } catch (error) {
    console.error('Ошибка подписки на канал:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 42. DELETE Отписка от канала
app.delete('/api/channels/:channelId/subscribe', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const userId = req.user.userId;

  try {
    const deleteQuery = `
      DELETE FROM channel_subscribers 
      WHERE channel_id = $1 AND user_id = $2
      RETURNING *
    `;
    
    const result = await pool.query(deleteQuery, [channelId, userId]);
    
    if (result.rows.length > 0) {
      res.json({ success: true, message: 'Вы отписались от канала' });
    } else {
      res.json({ success: false, message: 'Вы не были подписаны на этот канал' });
    }
  } catch (error) {
    console.error('Ошибка отписки от канала:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 43. GET Получение списка подписчиков канала
app.get('/api/channels/:channelId/subscribers', authMiddleware, async (req, res) => {
  const { channelId } = req.params;
  const userId = req.user.userId;

  try {
    const accessCheck = await pool.query(
      `SELECT 1 FROM channels WHERE id = $1 AND created_by = $2
       UNION
       SELECT 1 FROM channel_subscribers WHERE channel_id = $1 AND user_id = $2`,
      [channelId, userId]
    );

    if (accessCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Доступ запрещен' 
      });
    }

    const subscribersQuery = `
      SELECT 
        u.id,
        u.email_encrypted,
        u.nickname,
        u.name,
        u.avatar_url,
        u.avatar_color,
        cs.subscribed_at
      FROM channel_subscribers cs
      JOIN users u ON cs.user_id = u.id
      WHERE cs.channel_id = $1
      ORDER BY cs.subscribed_at DESC
    `;
    
    const result = await pool.query(subscribersQuery, [channelId]);
    
    const subscribers = result.rows.map(sub => {
      const decryptedName = sub.name ? decryptString(sub.name) : null;
      const decryptedNickname = sub.nickname ? decryptString(sub.nickname) : null;
      const decryptedEmail = sub.email_encrypted ? decryptString(sub.email_encrypted) : null;
      
      return {
        id: sub.id,
        display_name: decryptedNickname || decryptedName || decryptedEmail || `User ${sub.id}`,
        nickname: decryptedNickname,
        name: decryptedName,
        email: decryptedEmail,
        avatar_url: sub.avatar_url,
        avatar_color: sub.avatar_color,
        subscribed_at: sub.subscribed_at
      };
    });
    
    res.json({ 
      success: true, 
      subscribers: subscribers,
      count: subscribers.length
    });
  } catch (error) {
    console.error('Ошибка получения подписчиков:', error);
    res.status(500).json({ success: false, error: 'Ошибка сервера' });
  }
});

// 44. POST Проверка доступности ссылки канала
app.post('/api/channels/check-link', authMiddleware, async (req, res) => {
  try {
    const { channelLink } = req.body;
    
    if (!channelLink || channelLink.trim().length === 0) {
      return res.json({ available: false, error: 'Ссылка канала не может быть пустой' });
    }
    
    const cleanLink = channelLink.trim();
    
    const validLinkRegex = /^[a-zA-Z0-9_-]+$/;
    if (!validLinkRegex.test(cleanLink)) {
      return res.json({ 
        available: false, 
        error: 'Ссылка может содержать только английские буквы, цифры, _ и -' 
      });
    }
    
    const { rows } = await pool.query(
      `SELECT id FROM channels WHERE channel_link = $1`,
      [cleanLink]
    );
    
    const isTaken = rows.length > 0;
    
    res.json({ 
      available: !isTaken,
      taken: isTaken,
      message: isTaken ? 'Ссылка уже занята' : 'Ссылка свободна'
    });
    
  } catch (error) {
    console.error('Ошибка проверки ссылки канала:', error);
    res.status(500).json({ available: false, error: 'Ошибка сервера' });
  }
});

// 45. GET Получение списка контактов пользователя
app.get('/api/contacts', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    const { rows } = await pool.query(
      `SELECT 
        uc.id,
        uc.contact_name,
        uc.note,
        uc.created_at,
        uc.contact_email_hash,
        uc.contact_user_id,
        u.id as registered_user_id,
        u.email_encrypted,
        u.nickname,
        u.avatar_url,
        u.avatar_color
      FROM user_contacts uc
      LEFT JOIN users u ON uc.contact_user_id = u.id
      WHERE uc.user_id = $1
      ORDER BY uc.contact_name ASC`,
      [userId]
    );
    
    console.log(`📋 Найдено контактов для пользователя ${userId}: ${rows.length}`);
    
    const contacts = rows.map(row => {
      const contact = {
        id: row.id,
        contact_name: row.contact_name,
        note: row.note,
        created_at: row.created_at,
        is_registered: row.registered_user_id !== null,
        contact_user_id: row.contact_user_id
      };
      
      if (row.email_encrypted && row.registered_user_id) {
        const decryptedEmail = decryptString(row.email_encrypted);
        const decryptedNickname = row.nickname ? decryptString(row.nickname) : null;
        contact.contact_email = decryptedEmail;
        contact.nickname = decryptedNickname;
        contact.avatar_url = row.avatar_url;
        contact.avatar_color = row.avatar_color;
      } else {
        contact.contact_email = null;
        contact.nickname = null;
        contact.avatar_url = null;
        contact.avatar_color = null;
      }
      
      return contact;
    });
    
    console.log('📤 Отправляем контакты:', JSON.stringify(contacts, null, 2));
    
    res.json({
      success: true,
      contacts
    });
    
  } catch (error) {
    console.error('Ошибка получения контактов:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка получения контактов' 
    });
  }
});

// 46. POST Создание нового контакта
app.post('/api/contacts', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { contact_name, contact_email, note } = req.body;
    
    if (!contact_name || contact_name.trim().length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Имя контакта обязательно' 
      });
    }
    
    if (!contact_email || contact_email.trim().length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Почта контакта обязательна' 
      });
    }
    
    const cleanEmail = contact_email.trim().toLowerCase();
    
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Введите корректный email' 
      });
    }
    
    const cleanName = contact_name.trim();
    const emailHash = hashEmail(cleanEmail);
    
    const selfCheck = await pool.query(
      'SELECT id FROM users WHERE id = $1 AND email_hash = $2',
      [userId, emailHash]
    );
    
    if (selfCheck.rows.length > 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Вы не можете добавить себя в контакты' 
      });
    }
    
    const userCheck = await pool.query(
      'SELECT id, email_encrypted, nickname, avatar_url, avatar_color FROM users WHERE email_hash = $1',
      [emailHash]
    );
    
    const contactUserId = userCheck.rows.length > 0 ? userCheck.rows[0].id : null;
    
    console.log(`🔍 Поиск пользователя по email: ${cleanEmail}`);
    console.log(`👤 Найден пользователь: ${contactUserId ? 'Да (ID: ' + contactUserId + ')' : 'Нет'}`);
    
    const existingContact = await pool.query(
      'SELECT id FROM user_contacts WHERE user_id = $1 AND (contact_user_id = $2 OR (contact_user_id IS NULL AND contact_email_hash = $3))',
      [userId, contactUserId, emailHash]
    );
    
    if (existingContact.rows.length > 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Этот контакт уже добавлен' 
      });
    }
    
    const { rows } = await pool.query(
      `INSERT INTO user_contacts (user_id, contact_user_id, contact_name, note, contact_email_hash)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, contact_name, note, created_at, contact_user_id`,
      [userId, contactUserId, cleanName, note ? note.trim() : null, emailHash]
    );
    
    console.log('✅ Контакт создан:', rows[0]);
    
    const contactData = {
      id: rows[0].id,
      contact_name: rows[0].contact_name,
      note: rows[0].note,
      created_at: rows[0].created_at,
      contact_user_id: rows[0].contact_user_id,
      is_registered: contactUserId !== null
    };
    
    if (userCheck.rows.length > 0) {
      const decryptedEmail = decryptString(userCheck.rows[0].email_encrypted);
      const decryptedNickname = userCheck.rows[0].nickname ? decryptString(userCheck.rows[0].nickname) : null;
      contactData.contact_email = decryptedEmail;
      contactData.nickname = decryptedNickname;
      contactData.avatar_url = userCheck.rows[0].avatar_url;
      contactData.avatar_color = userCheck.rows[0].avatar_color;
    } else {
      contactData.contact_email = null;
      contactData.nickname = null;
      contactData.avatar_url = null;
      contactData.avatar_color = null;
    }
    
    res.status(201).json({
      success: true,
      message: 'Контакт успешно добавлен',
      contact: contactData
    });
    
  } catch (error) {
    console.error('Ошибка создания контакта:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка создания контакта' 
    });
  }
});

// 46.1 PUT Обновление контакта
app.put('/api/contacts/:contactId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const contactId = parseInt(req.params.contactId);
    const { contact_name, note } = req.body;
    
    if (!contact_name || contact_name.trim().length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Имя контакта обязательно' 
      });
    }
    
    const cleanName = contact_name.trim();
    const cleanNote = note ? note.trim() : null;
    
    const contactCheck = await pool.query(
      'SELECT id, contact_user_id FROM user_contacts WHERE id = $1 AND user_id = $2',
      [contactId, userId]
    );
    
    if (contactCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Контакт не найден' 
      });
    }
    
    const { rows } = await pool.query(
      `UPDATE user_contacts 
       SET contact_name = $1, note = $2, updated_at = NOW()
       WHERE id = $3 AND user_id = $4
       RETURNING id, contact_name, note, updated_at, contact_user_id`,
      [cleanName, cleanNote, contactId, userId]
    );
        
    res.status(200).json({
      success: true,
      message: 'Контакт успешно обновлён',
      contact: {
        id: rows[0].id,
        contact_name: rows[0].contact_name,
        note: rows[0].note,
        updated_at: rows[0].updated_at,
        contact_user_id: rows[0].contact_user_id
      }
    });
    
  } catch (error) {
    console.error('Ошибка обновления контакта:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка обновления контакта' 
    });
  }
});

// 46.2 DELETE Удаление контакта
app.delete('/api/contacts/:contactId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const contactId = parseInt(req.params.contactId);
        
    const contactCheck = await pool.query(
      'SELECT id, contact_name FROM user_contacts WHERE id = $1 AND user_id = $2',
      [contactId, userId]
    );
    
    if (contactCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Контакт не найден' 
      });
    }
    
    const contactName = contactCheck.rows[0].contact_name;
    
    await pool.query(
      'DELETE FROM user_contacts WHERE id = $1 AND user_id = $2',
      [contactId, userId]
    );
        
    res.status(200).json({
      success: true,
      message: `Контакт "${contactName}" успешно удалён`
    });
    
  } catch (error) {
    console.error('Ошибка удаления контакта:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка удаления контакта' 
    });
  }
});

// 47. GET Поиск по чатам, контактам и каналам
app.get('/api/search', authMiddleware, async (req, res) => {
  try {
    const { q } = req.query;
    const userId = req.user.userId;

    if (!q || q.trim().length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Search query is required'
      });
    }

    const searchQuery = `%${q.trim().toLowerCase()}%`;

    const chatsQuery = `
      SELECT DISTINCT
        c.id,
        c.title as name,
        COALESCE(
          (SELECT m.text 
           FROM messages m 
           WHERE m.chat_id = c.id 
           ORDER BY m.created_at DESC 
           LIMIT 1),
          'Нет сообщений'
        ) as description,
        COALESCE(
          (SELECT m.created_at 
           FROM messages m 
           WHERE m.chat_id = c.id 
           ORDER BY m.created_at DESC 
           LIMIT 1),
          c.created_at
        ) as lastInteraction,
        c.is_private as type
      FROM chats c
      INNER JOIN chat_participants cp ON c.id = cp.chat_id
      WHERE cp.user_id = $1
        AND LOWER(c.title) LIKE $2
      ORDER BY lastInteraction DESC
      LIMIT 10
    `;

    const chats = await pool.query(chatsQuery, [userId, searchQuery]);

    const contactsQuery = `
      SELECT DISTINCT
        uc.id as contact_id,
        uc.contact_user_id as id,
        uc.contact_name as name,
        COALESCE(uc.note, '') as description,
        uc.created_at as lastInteraction,
        u.nickname,
        u.email_encrypted,
        u.avatar_url,
        u.avatar_color
      FROM user_contacts uc
      LEFT JOIN users u ON uc.contact_user_id = u.id
      WHERE uc.user_id = $1
        AND (
          LOWER(COALESCE(uc.contact_name, '')) LIKE $2
          OR LOWER(COALESCE(u.nickname, '')) LIKE $2
          OR LOWER(COALESCE(uc.note, '')) LIKE $2
        )
      ORDER BY uc.created_at DESC
      LIMIT 10
    `;

    const contacts = await pool.query(contactsQuery, [userId, searchQuery]);

    const processedContacts = await Promise.all(contacts.rows.map(async (contact) => {
      let displayName = contact.name;
      
      if (contact.contact_user_id && contact.email_encrypted) {
        try {
          const decryptedEmail = decryptString(contact.email_encrypted);
          const decryptedNickname = contact.nickname ? decryptString(contact.nickname) : null;
          
          if (decryptedNickname && decryptedNickname.trim()) {
            displayName = decryptedNickname.trim();
          } else {
            displayName = decryptedEmail || contact.name;
          }
        } catch (error) {
          console.error('❌ Ошибка расшифровки email контакта:', error.message);
          displayName = contact.name;
        }
      }
      
      return {
        id: contact.contact_user_id || contact.contact_id,
        name: displayName,
        description: contact.description,
        lastInteraction: contact.lastinteraction,
        is_contact: true,
        avatar_url: contact.avatar_url,
        avatar_color: contact.avatar_color,
        nickname: contact.nickname
      };
    }));

    const channelsQuery = `
      SELECT 
        ch.id,
        ch.name,
        COALESCE(ch.description, '') as description,
        ch.created_at as lastInteraction,
        (SELECT COUNT(*) FROM channel_members WHERE channel_id = ch.id) as member_count,
        EXISTS(
          SELECT 1 FROM channel_members 
          WHERE channel_id = ch.id AND user_id = $1
        ) as is_member
      FROM channels ch
      WHERE 
        LOWER(ch.name) LIKE $2
        OR LOWER(COALESCE(ch.description, '')) LIKE $2
      ORDER BY member_count DESC, ch.created_at DESC
      LIMIT 10
    `;

    const channels = await pool.query(channelsQuery, [userId, searchQuery]);

    const usersQuery = `
      WITH decrypted_users AS (
        SELECT 
          u.id,
          u.nickname,
          u.email_encrypted,
          u.avatar_url,
          u.avatar_color,
          u.created_at,
          CASE 
            WHEN u.email_encrypted IS NOT NULL THEN (
              1
            )
            ELSE NULL
          END as has_email
        FROM users u
        WHERE u.id != $1
          AND NOT EXISTS (
            SELECT 1 
            FROM user_contacts uc 
            WHERE uc.contact_user_id = u.id 
              AND uc.user_id = $1
          )
      )
      SELECT * FROM decrypted_users
      WHERE 
        LOWER(COALESCE(nickname, '')) LIKE $2
      ORDER BY created_at DESC
      LIMIT 10
    `;

    const users = await pool.query(usersQuery, [userId, searchQuery]);

    const processedUsers = await Promise.all(users.rows
      .filter(async (user) => {
        try {
          if (user.email_encrypted) {
            const decryptedEmail = decryptString(user.email_encrypted);
            return decryptedEmail.toLowerCase().includes(q.trim().toLowerCase());
          }
          return false;
        } catch (error) {
          return false;
        }
      })
      .map(async (user) => {
        let displayName = `User ${user.id}`;
        let email = null;
        let decryptedNickname = null;
        
        try {
          email = decryptString(user.email_encrypted);
          decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
          
          if (decryptedNickname && decryptedNickname.trim()) {
            displayName = decryptedNickname.trim();
          } else if (email) {
            displayName = email;
          }
        } catch (error) {
          console.error('❌ Ошибка расшифровки email пользователя:', error.message);
        }
        
        return {
          id: user.id,
          name: displayName,
          description: 'Пользователь',
          lastInteraction: user.created_at,
          is_user: true,
          avatar_url: user.avatar_url,
          avatar_color: user.avatar_color,
          nickname: decryptedNickname,
          email: email
        };
      }));

    const filteredUsers = await Promise.all(processedUsers);

    console.log('🔍 Результаты поиска:', {
      query: q,
      chats: chats.rows.length,
      contacts: processedContacts.length,
      channels: channels.rows.length,
      users: filteredUsers.length
    });

    return res.json({
      success: true,
      query: q,
      chats: chats.rows.map(chat => ({
        id: chat.id,
        name: chat.name,
        description: chat.description,
        lastInteraction: chat.lastinteraction,
        type: chat.type ? 'private' : 'group'
      })),
      contacts: processedContacts,
      users: filteredUsers,
      channels: channels.rows.map(channel => ({
        id: channel.id,
        name: channel.name,
        description: channel.description,
        lastInteraction: channel.lastinteraction,
        memberCount: parseInt(channel.member_count) || 0,
        isMember: channel.is_member
      }))
    });

  } catch (error) {
    console.error('❌ Ошибка поиска:', error);
    console.error('❌ Stack trace:', error.stack);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 48. GET Получение настроек уведомлений для чата
app.get('/api/chats/:chatId/notification-settings', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const userId = req.user.userId;

    const chatCheck = await pool.query(
      `
      SELECT 1
      FROM chats c
      LEFT JOIN chat_participants cp ON c.id = cp.chat_id
      WHERE c.id = $1 AND (c.is_private = false OR cp.user_id = $2)
      `,
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Чат не найден или нет доступа' });
    }

    const settingsResult = await pool.query(
      `
      SELECT notifications_enabled, mute_duration, muted_until
      FROM chat_notification_settings
      WHERE chat_id = $1 AND user_id = $2
      `,
      [chatId, userId]
    );

    if (settingsResult.rows.length === 0) {
      await pool.query(
        `
        INSERT INTO chat_notification_settings
          (chat_id, user_id, notifications_enabled, created_at, updated_at)
        VALUES ($1, $2, TRUE, NOW(), NOW())
        `,
        [chatId, userId]
      );

      return res.json({
        notifications_enabled: true,
        mute_duration: null,
        muted_until: null,
      });
    }

    const settings = settingsResult.rows[0];

    if (settings.muted_until && new Date(settings.muted_until) < new Date()) {
      await pool.query(
        `
        UPDATE chat_notification_settings
        SET notifications_enabled = TRUE,
            mute_duration = NULL,
            muted_until = NULL,
            updated_at = NOW()
        WHERE chat_id = $1 AND user_id = $2
        `,
        [chatId, userId]
      );

      return res.json({
        notifications_enabled: true,
        mute_duration: null,
        muted_until: null,
      });
    }

    res.json(settings);
  } catch (error) {
    console.error('GET notification-settings error:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// 49. PUT Обновление настроек уведомлений
app.put('/api/chats/:chatId/notification-settings', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const userId = req.user.userId;
    const { notifications_enabled, mute_duration, muted_until } = req.body;

    const chatCheck = await pool.query(
      `
      SELECT 1
      FROM chats c
      LEFT JOIN chat_participants cp ON c.id = cp.chat_id
      WHERE c.id = $1 AND (c.is_private = false OR cp.user_id = $2)
      `,
      [chatId, userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Чат не найден или нет доступа' });
    }

    await pool.query(
      `
      INSERT INTO chat_notification_settings
        (chat_id, user_id, notifications_enabled, mute_duration, muted_until, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
      ON CONFLICT (chat_id, user_id)
      DO UPDATE SET
        notifications_enabled = EXCLUDED.notifications_enabled,
        mute_duration = EXCLUDED.mute_duration,
        muted_until = EXCLUDED.muted_until,
        updated_at = NOW()
      `,
      [chatId, userId, notifications_enabled, mute_duration, muted_until]
    );

    await pool.query(
      `
      INSERT INTO notification_settings_logs
        (chat_id, user_id, action, mute_duration, created_at)
      VALUES ($1, $2, $3, $4, NOW())
      `,
      [chatId, userId, notifications_enabled ? 'enabled' : 'disabled', mute_duration]
    );

    res.json({ success: true });
  } catch (error) {
    console.error('PUT notification-settings error:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// 50. POST Эндпоинт для массового получения настроек уведомлений
app.post('/api/chats/notification-settings/batch', authMiddleware, async (req, res) => {
  try {
    const { chatIds } = req.body;
    const userId = req.user.userId;

    if (!Array.isArray(chatIds) || chatIds.length === 0) {
      return res.status(400).json({ error: 'chatIds должен быть массивом' });
    }

    const result = await pool.query(
      `
      SELECT chat_id, notifications_enabled, mute_duration, muted_until
      FROM chat_notification_settings
      WHERE user_id = $1 AND chat_id = ANY($2::int[])
      `,
      [userId, chatIds]
    );

    const map = {};
    result.rows.forEach(row => {
      map[row.chat_id] = {
        notifications_enabled: row.notifications_enabled,
        mute_duration: row.mute_duration,
        muted_until: row.muted_until,
      };
    });

    chatIds.forEach(chatId => {
      if (!map[chatId]) {
        map[chatId] = {
          notifications_enabled: true,
          mute_duration: null,
          muted_until: null,
        };
      }
    });

    res.json(map);
  } catch (error) {
    console.error('Batch notification-settings error:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// 51. GET Получение истекших отключений уведомлений
app.get('/api/chats/notification-settings/expired', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;

    const expired = await pool.query(
      `
      SELECT cns.chat_id, c.title, cns.muted_until
      FROM chat_notification_settings cns
      JOIN chats c ON c.id = cns.chat_id
      WHERE cns.user_id = $1
        AND cns.notifications_enabled = FALSE
        AND cns.muted_until IS NOT NULL
        AND cns.muted_until < NOW()
      `,
      [userId]
    );

    if (expired.rows.length > 0) {
      const chatIds = expired.rows.map(r => r.chat_id);

      await pool.query(
        `
        UPDATE chat_notification_settings
        SET notifications_enabled = TRUE,
            mute_duration = NULL,
            muted_until = NULL,
            updated_at = NOW()
        WHERE user_id = $1 AND chat_id = ANY($2::int[])
        `,
        [userId, chatIds]
      );

      for (const row of expired.rows) {
        await pool.query(
          `
          INSERT INTO notification_settings_logs
            (chat_id, user_id, action, created_at)
          VALUES ($1, $2, 'auto_enabled', NOW())
          `,
          [row.chat_id, userId]
        );
      }
    }

    res.json({
      expired_count: expired.rows.length,
      chats: expired.rows,
    });
  } catch (error) {
    console.error('Expired mutes error:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// 52. POST Сохранение 1 ИИ сообщения (ИСПРАВЛЕННЫЙ - с шифрованием)
app.post('/api/ai/messages/save', authMiddleware, async (req, res) => {
  try {
    const { chat_id, message_id, text, is_from_user, created_at, is_streaming, user_id } = req.body;

    if (!chat_id || !message_id || text === undefined || is_from_user === undefined || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, message_id, text, is_from_user, user_id'
      });
    }

    const encryptedText = encryptMessage(text);

    const chatCheck = await pool.query(
      'SELECT id, title FROM ai_chats WHERE chat_id = $1 AND user_id = $2',
      [chat_id, user_id]
    );

    if (chatCheck.rows.length === 0 && is_from_user) {
      const title = text.split(/[.!?]/)[0].trim();
      const chatTitle = title.length > 50 ? title.substring(0, 47) + '...' : title;
      
      await pool.query(
        `INSERT INTO ai_chats (chat_id, title, last_message, last_message_time, is_pinned, created_at, user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          chat_id,
          chatTitle,
          text.substring(0, 100),
          created_at || new Date().toISOString(),
          false,
          new Date().toISOString(),
          user_id
        ]
      );
      console.log(`✅ Создан новый AI чат ${chat_id} для пользователя ${user_id} с заголовком: ${chatTitle}`);
    }

    const existingMessage = await pool.query(
      'SELECT id FROM ai_messages WHERE message_id = $1 AND user_id = $2',
      [message_id, user_id]
    );

    let result;
    if (existingMessage.rows.length > 0) {
      result = await pool.query(
        `UPDATE ai_messages 
         SET text = $1, is_streaming = $2
         WHERE message_id = $3 AND user_id = $4
         RETURNING id`,
        [encryptedText, is_streaming || false, message_id, user_id]
      );
      console.log(`📝 Обновлено AI сообщение ${message_id} для пользователя ${user_id}`);
    } else {
      result = await pool.query(
        `INSERT INTO ai_messages 
         (chat_id, message_id, text, is_from_user, created_at, is_streaming, user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          chat_id,
          message_id,
          encryptedText,
          is_from_user,
          created_at || new Date().toISOString(),
          is_streaming || false,
          user_id
        ]
      );
      console.log(`💾 Сохранено новое AI сообщение ${message_id} для пользователя ${user_id} (${is_from_user ? 'пользователь' : 'ИИ'})`);
    }

    if (chatCheck.rows.length > 0 || (chatCheck.rows.length === 0 && is_from_user)) {
      await pool.query(
        `UPDATE ai_chats 
         SET last_message = $1, last_message_time = $2
         WHERE chat_id = $3 AND user_id = $4`,
        [
          text.substring(0, 100),
          created_at || new Date().toISOString(),
          chat_id,
          user_id
        ]
      );
    }

    res.json({
      success: true,
      message: 'Сообщение сохранено',
      id: result.rows[0]?.id
    });

  } catch (error) {
    console.error('Error saving AI message:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка сохранения сообщения',
      error: error.message
    });
  }
});

// 53. POST Сохранить несколько сообщений AI чата (ИСПРАВЛЕННЫЙ - с шифрованием)
app.post('/api/ai/messages/save-batch', authMiddleware, async (req, res) => {
  try {
    const { messages, user_id } = req.body;

    if (!messages || !Array.isArray(messages) || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимы поля: messages (массив), user_id'
      });
    }

    const savedMessages = [];
    let chatCreated = false;
    let chat_id = null;

    if (messages.length > 0 && messages[0].chat_id) {
      chat_id = messages[0].chat_id;
    }

    if (chat_id) {
      const chatCheck = await pool.query(
        'SELECT id FROM ai_chats WHERE chat_id = $1 AND user_id = $2',
        [chat_id, user_id]
      );

      const firstUserMessage = messages.find(msg => msg.is_from_user);
      
      if (chatCheck.rows.length === 0 && firstUserMessage) {
        const decryptedText = decryptMessage(firstUserMessage.text) || firstUserMessage.text;
        const title = decryptedText.split(/[.!?]/)[0].trim();
        const chatTitle = title.length > 50 ? title.substring(0, 47) + '...' : title;
        
        await pool.query(
          `INSERT INTO ai_chats (chat_id, title, last_message, last_message_time, is_pinned, created_at, user_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            chat_id,
            chatTitle,
            decryptedText.substring(0, 100),
            firstUserMessage.created_at || new Date().toISOString(),
            false,
            new Date().toISOString(),
            user_id
          ]
        );
        chatCreated = true;
        console.log(`✅ Создан новый AI чат ${chat_id} через batch для пользователя ${user_id} с заголовком: ${chatTitle}`);
      }
    }

    for (const msg of messages) {
      const { chat_id: msg_chat_id, message_id, text, is_from_user, created_at, is_streaming } = msg;

      if (is_streaming) continue;

      const encryptedText = encryptMessage(text || '');

      const existingMessage = await pool.query(
        'SELECT id FROM ai_messages WHERE message_id = $1 AND user_id = $2',
        [message_id, user_id]
      );

      let result;
      if (existingMessage.rows.length > 0) {
        result = await pool.query(
          `UPDATE ai_messages 
           SET text = $1
           WHERE message_id = $2 AND user_id = $3
           RETURNING id`,
          [encryptedText, message_id, user_id]
        );
      } else {
        result = await pool.query(
          `INSERT INTO ai_messages 
           (chat_id, message_id, text, is_from_user, created_at, is_streaming, user_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id`,
          [
            msg_chat_id,
            message_id,
            encryptedText,
            is_from_user,
            created_at || new Date().toISOString(),
            false,
            user_id
          ]
        );
      }

      savedMessages.push({
        message_id,
        id: result.rows[0]?.id
      });

      if (text && !is_from_user && msg_chat_id) {
        await pool.query(
          `UPDATE ai_chats 
           SET last_message = $1, last_message_time = $2
           WHERE chat_id = $3 AND user_id = $4`,
          [
            text.substring(0, 100),
            created_at || new Date().toISOString(),
            msg_chat_id,
            user_id
          ]
        );
      }
    }

    res.json({
      success: true,
      message: `Сохранено ${savedMessages.length} сообщений`,
      savedMessages,
      chat_created: chatCreated
    });

  } catch (error) {
    console.error('Error saving AI messages batch:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка сохранения сообщений',
      error: error.message
    });
  }
});

// 54. GET Получить историю сообщений AI чата (ИСПРАВЛЕННЫЙ - с дешифровкой)
app.get('/api/ai/messages/history', authMiddleware, async (req, res) => {
  try {
    const { chat_id, user_id } = req.query;

    if (!chat_id || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые параметры: chat_id, user_id'
      });
    }

    console.log(`📜 Запрос истории AI чата ${chat_id} для пользователя ${user_id}`);

    const result = await pool.query(
      `SELECT 
         id,
         message_id,
         text,
         is_from_user,
         created_at,
         is_streaming
       FROM ai_messages 
       WHERE chat_id = $1 AND user_id = $2 
       ORDER BY created_at ASC`,
      [chat_id, user_id]
    );

    console.log(`📜 Найдено ${result.rows.length} сообщений в AI чате ${chat_id}`);

    const messages = result.rows.map(row => {
      try {
        const decryptedText = decryptMessage(row.text);
        return {
          message_id: row.message_id,
          id: row.id,
          text: decryptedText || '[Ошибка дешифровки]',
          is_from_user: row.is_from_user,
          created_at: row.created_at,
          is_streaming: row.is_streaming
        };
      } catch (error) {
        console.error(`❌ Ошибка дешифровки сообщения ${row.message_id}:`, error.message);
        return {
          message_id: row.message_id,
          id: row.id,
          text: '[Ошибка дешифровки]',
          is_from_user: row.is_from_user,
          created_at: row.created_at,
          is_streaming: row.is_streaming
        };
      }
    });

    res.json({
      success: true,
      messages: messages
    });

  } catch (error) {
    console.error('Error loading AI messages history:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка загрузки истории сообщений',
      error: error.message
    });
  }
});

// 55. GET Получить список AI чатов пользователя
app.get('/api/ai/chats', authMiddleware, async (req, res) => {
  try {
    const { user_id } = req.query;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходим параметр: user_id'
      });
    }

    console.log(`📋 Запрос списка AI чатов для пользователя ${user_id}`);

    const result = await pool.query(
      `SELECT 
         c.id,
         c.chat_id,
         c.title,
         c.last_message,
         c.last_message_time,
         c.is_pinned,
         c.created_at,
         c.user_id,
         COUNT(m.id) as message_count,
         (SELECT m2.text 
          FROM ai_messages m2 
          WHERE m2.chat_id = c.chat_id 
            AND m2.user_id = c.user_id 
            AND m2.is_from_user = true 
          ORDER BY m2.created_at ASC 
          LIMIT 1) as first_user_message
       FROM ai_chats c
       LEFT JOIN ai_messages m ON c.chat_id = m.chat_id AND c.user_id = m.user_id
       WHERE c.user_id = $1 
       GROUP BY c.id, c.chat_id, c.title, c.last_message, c.last_message_time, 
                c.is_pinned, c.created_at, c.user_id
       HAVING COUNT(m.id) > 0
       ORDER BY 
         c.is_pinned DESC,
         c.last_message_time DESC NULLS LAST,
         c.created_at DESC`,
      [user_id]
    );

    console.log(`📋 Найдено ${result.rows.length} AI чатов для пользователя ${user_id}`);

    const chats = await Promise.all(result.rows.map(async (row) => {
      let displayTitle = row.title;
      
      if (row.first_user_message) {
        try {
          const decryptedFirstMessage = decryptMessage(row.first_user_message);
          const firstSentence = decryptedFirstMessage.split(/[.!?]/)[0].trim();
          displayTitle = firstSentence.length > 50 
            ? firstSentence.substring(0, 47) + '...' 
            : firstSentence;
        } catch (error) {
          console.error(`❌ Ошибка дешифровки первого сообщения для чата ${row.chat_id}:`, error.message);
          displayTitle = row.title;
        }
      }
      
      return {
        ...row,
        display_title: displayTitle || 'Новый чат'
      };
    }));

    res.json({
      success: true,
      chats: chats
    });

  } catch (error) {
    console.error('Error loading AI chats:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка загрузки AI чатов',
      error: error.message
    });
  }
});

// 56. POST Сохранить/обновить AI чат
app.post('/api/ai/chats/save', authMiddleware, async (req, res) => {
  try {
    const { chat_id, title, last_message, is_pinned, user_id, created_at } = req.body;

    if (!chat_id || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, user_id'
      });
    }

    const existingChat = await pool.query(
      'SELECT id, title FROM ai_chats WHERE chat_id = $1 AND user_id = $2',
      [chat_id, user_id]
    );

    let result;
    if (existingChat.rows.length > 0) {
      if (title || last_message !== undefined || is_pinned !== undefined) {
        const updateFields = [];
        const queryParams = [];
        let paramIndex = 1;
        
        if (title !== undefined) {
          updateFields.push(`title = $${paramIndex++}`);
          queryParams.push(title || 'Новый чат');
        }
        
        if (last_message !== undefined) {
          updateFields.push(`last_message = $${paramIndex++}`);
          queryParams.push(last_message || '');
          updateFields.push(`last_message_time = $${paramIndex++}`);
          queryParams.push(created_at || new Date().toISOString());
        }
        
        if (is_pinned !== undefined) {
          updateFields.push(`is_pinned = $${paramIndex++}`);
          let pinValue = false;
          if (typeof is_pinned === 'boolean') {
            pinValue = is_pinned;
          } else if (typeof is_pinned === 'string') {
            pinValue = is_pinned.toLowerCase() === 'true';
          } else {
            pinValue = Boolean(is_pinned);
          }
          queryParams.push(pinValue);
        }
        
        queryParams.push(chat_id, user_id);
        
        const updateQuery = `
          UPDATE ai_chats 
          SET ${updateFields.join(', ')}
          WHERE chat_id = $${paramIndex} AND user_id = $${paramIndex + 1}
          RETURNING id
        `;
        
        result = await pool.query(updateQuery, queryParams);
      } else {
        result = { rows: [{ id: existingChat.rows[0].id }] };
      }
    } else {
      if (last_message === undefined && title === undefined) {
        return res.status(400).json({
          success: false,
          message: 'Нельзя создать пустой AI чат. Укажите хотя бы title или last_message.'
        });
      }
      
      let pinValue = false;
      if (is_pinned !== undefined) {
        if (typeof is_pinned === 'boolean') {
          pinValue = is_pinned;
        } else if (typeof is_pinned === 'string') {
          pinValue = is_pinned.toLowerCase() === 'true';
        } else {
          pinValue = Boolean(is_pinned);
        }
      }
      
      const chatTitle = title || 'Новый чат';
      
      result = await pool.query(
        `INSERT INTO ai_chats 
         (chat_id, title, last_message, last_message_time, is_pinned, created_at, user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          chat_id,
          chatTitle,
          last_message || '',
          created_at || new Date().toISOString(),
          pinValue,
          new Date().toISOString(),
          user_id
        ]
      );
      console.log(`✅ Создан AI чат для пользователя ${user_id} с заголовком: ${chatTitle}`);
    }

    res.json({
      success: true,
      message: 'Чат сохранен',
      id: result.rows[0]?.id,
      existed: existingChat.rows.length > 0
    });

  } catch (error) {
    console.error('Error saving AI chat:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка сохранения чата',
      error: error.message
    });
  }
});

// 57. PUT Переименовать AI чат
app.put('/api/ai/chats/rename', authMiddleware, async (req, res) => {
  try {
    const { chat_id, title, user_id } = req.body;

    if (!chat_id || !title || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, title, user_id'
      });
    }

    const result = await pool.query(
      `UPDATE ai_chats 
       SET title = $1
       WHERE chat_id = $2 AND user_id = $3
       RETURNING id`,
      [title, chat_id, user_id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Чат не найден'
      });
    }

    res.json({
      success: true,
      message: 'Чат переименован'
    });

  } catch (error) {
    console.error('Error renaming AI chat:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка переименования чата',
      error: error.message
    });
  }
});

// 58. PUT Закрепить/открепить AI чат
app.put('/api/ai/chats/toggle-pin', authMiddleware, async (req, res) => {
  try {
    const { chat_id, is_pinned, user_id } = req.body;

    if (!chat_id || is_pinned === undefined || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, is_pinned, user_id'
      });
    }

    const result = await pool.query(
      `UPDATE ai_chats 
       SET is_pinned = $1
       WHERE chat_id = $2 AND user_id = $3
       RETURNING id`,
      [is_pinned, chat_id, user_id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Чат не найден'
      });
    }

    res.json({
      success: true,
      message: is_pinned ? 'Чат закреплен' : 'Чат откреплен'
    });

  } catch (error) {
    console.error('Error toggling AI chat pin:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка изменения состояния закрепления',
      error: error.message
    });
  }
});

// 59. PUT Обновить последнее сообщение в AI чате
app.put('/api/ai/chats/update-last-message', authMiddleware, async (req, res) => {
  try {
    const { chat_id, last_message, user_id } = req.body;

    if (!chat_id || !last_message || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, last_message, user_id'
      });
    }

    const result = await pool.query(
      `UPDATE ai_chats 
       SET last_message = $1, 
           last_message_time = CURRENT_TIMESTAMP
       WHERE chat_id = $2 AND user_id = $3
       RETURNING id`,
      [last_message.substring(0, 100), chat_id, user_id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Чат не найден'
      });
    }

    res.json({
      success: true,
      message: 'Последнее сообщение обновлено'
    });

  } catch (error) {
    console.error('Error updating AI chat last message:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка обновления последнего сообщения',
      error: error.message
    });
  }
});

// 60. DELETE Удалить AI чат
app.delete('/api/ai/chats/delete', authMiddleware, async (req, res) => {
  try {
    const { chat_id, user_id } = req.query;

    if (!chat_id || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые параметры: chat_id, user_id'
      });
    }

    console.log(`🗑️  Попытка удалить AI чат ${chat_id} для пользователя ${user_id}`);

    await pool.query('BEGIN');

    try {
      const deleteMessagesResult = await pool.query(
        'DELETE FROM ai_messages WHERE chat_id = $1 AND user_id = $2 RETURNING id',
        [chat_id, user_id]
      );
      
      console.log(`🗑️  Удалено ${deleteMessagesResult.rowCount} сообщений из AI чата ${chat_id}`);

      const deleteChatResult = await pool.query(
        'DELETE FROM ai_chats WHERE chat_id = $1 AND user_id = $2 RETURNING id',
        [chat_id, user_id]
      );

      await pool.query('COMMIT');

      if (deleteChatResult.rowCount === 0) {
        console.log(`⚠️  AI чат ${chat_id} не найден для пользователя ${user_id}`);
        return res.status(404).json({
          success: false,
          message: 'Чат не найден'
        });
      }

      console.log(`✅ Успешно удален AI чат ${chat_id} для пользователя ${user_id}`);

      res.json({
        success: true,
        message: 'Чат и все сообщения удалены',
        deleted_messages: deleteMessagesResult.rowCount,
        deleted_chat: deleteChatResult.rowCount
      });

    } catch (error) {
      await pool.query('ROLLBACK');
      throw error;
    }

  } catch (error) {
    console.error('Error deleting AI chat:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка удаления чата',
      error: error.message
    });
  }
});

// 61. POST Создать AI чат при открытии (но только с базовой информацией)
app.post('/api/ai/chats/create', authMiddleware, async (req, res) => {
  try {
    const { chat_id, title, user_id } = req.body;

    if (!chat_id || !user_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, user_id'
      });
    }

    const existingChat = await pool.query(
      'SELECT id FROM ai_chats WHERE chat_id = $1 AND user_id = $2',
      [chat_id, user_id]
    );

    if (existingChat.rows.length > 0) {
      return res.json({
        success: true,
        message: 'Чат уже существует',
        id: existingChat.rows[0].id,
        existed: true
      });
    }

    const result = await pool.query(
      `INSERT INTO ai_chats 
       (chat_id, title, created_at, user_id)
       VALUES ($1, $2, $3, $4)
       RETURNING id`,
      [
        chat_id,
        title || 'Новый чат с ИИ',
        new Date().toISOString(),
        user_id
      ]
    );

    console.log(`✅ Создан AI чат ${chat_id} при открытии для пользователя ${user_id}`);

    res.json({
      success: true,
      message: 'Чат создан',
      id: result.rows[0]?.id,
      existed: false
    });

  } catch (error) {
    console.error('Error creating AI chat:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка создания чата',
      error: error.message
    });
  }
});

// 62. POST Создать новую папку
app.post('/api/folders', authMiddleware, uploadAvatar.single('avatar'), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const userId = req.user.userId;
    const { name, avatar_color, chat_ids } = req.body;
    
    console.log('📁 Create folder request:', {
      userId,
      name,
      avatar_color,
      chat_ids: chat_ids ? JSON.parse(chat_ids) : [],
      hasFile: !!req.file
    });
    
    const trimmedName = name ? name.trim() : '';
    
    if (!trimmedName) {
      await client.query('ROLLBACK');
      return res.status(400).json({ 
        success: false, 
        error: 'Название папки обязательно' 
      });
    }
    
    const existingFolder = await client.query(
      'SELECT id FROM folders WHERE name = $1 AND user_id = $2',
      [trimmedName, userId]
    );
    
    if (existingFolder.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ 
        success: false, 
        error: 'Папка с таким названием уже существует' 
      });
    }
    
    let avatarUrl = null;
    if (req.file) {
      try {
        const buffer = req.file.buffer;
        
        if (buffer.length < 100) {
          await client.query('ROLLBACK');
          return res.status(400).json({ 
            success: false, 
            error: 'Изображение слишком маленькое' 
          });
        }
        
        avatarUrl = await uploadToS3Avatar(buffer);
        
      } catch (error) {
        console.error('🚨 Avatar upload failed:', error.message);
        await client.query('ROLLBACK');
        return res.status(400).json({ 
          success: false,
          error: 'Ошибка загрузки аватара',
          details: error.message 
        });
      }
    }
    
    const folderResult = await client.query(
      `INSERT INTO folders (name, avatar_color, avatar_url, user_id, created_at, updated_at)
       VALUES ($1, $2, $3, $4, NOW(), NOW())
       RETURNING id, name, avatar_color, avatar_url, user_id, created_at, updated_at`,
      [trimmedName, avatar_color || '#2196F3', avatarUrl, userId]
    );
    
    const folderId = folderResult.rows[0].id;
    
    if (chat_ids) {
      try {
        const chatIdsArray = JSON.parse(chat_ids);
        
        if (Array.isArray(chatIdsArray) && chatIdsArray.length > 0) {
          const validChatIds = [];
          for (const chatId of chatIdsArray) {
            const participantCheck = await client.query(
              'SELECT id FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
              [chatId, userId]
            );
            
            if (participantCheck.rows.length > 0) {
              validChatIds.push(chatId);
            }
          }
          
          if (validChatIds.length > 0) {
            for (const chatId of validChatIds) {
              await client.query(
                `INSERT INTO folder_chats (folder_id, chat_id, added_at)
                 VALUES ($1, $2, NOW())`,
                [folderId, chatId]
              );
            }
          }
        }
      } catch (parseError) {
        console.error('Error parsing chat_ids:', parseError);
      }
    }
    
    const folder = folderResult.rows[0];
    
    const chatsResult = await client.query(
      `SELECT c.id
       FROM folder_chats fc
       INNER JOIN chats c ON fc.chat_id = c.id
       WHERE fc.folder_id = $1`,
      [folderId]
    );
    
    const chatIds = chatsResult.rows.map(row => row.id);
    let chats = [];
    
    if (chatIds.length > 0) {
      const placeholders = chatIds.map((_, i) => `$${i + 1}`).join(',');
      const chatQuery = `
        SELECT 
            c.id,
            c.title,
            c.description,
            c.created_at,
            c.is_private,
            c.is_pinned,
            c.is_muted,
            c.is_channel,
            (
                SELECT json_agg(user_id)
                FROM chat_participants cp
                WHERE cp.chat_id = c.id
            ) as participants
         FROM chats c
         WHERE c.id IN (${placeholders})
      `;
      
      const detailedChats = await client.query(chatQuery, chatIds);
      
      for (const chatRow of detailedChats.rows) {
        const lastMessageResult = await client.query(
          `SELECT m.text, m.created_at, m.user_id
           FROM messages m
           WHERE m.chat_id = $1
           ORDER BY m.created_at DESC
           LIMIT 1`,
          [chatRow.id]
        );
        
        const unreadResult = await client.query(
          `SELECT COUNT(*) as count
           FROM messages m
           WHERE m.chat_id = $1 
              AND m.user_id != $2
              AND m.created_at > COALESCE(
                  (SELECT m2.created_at 
                   FROM messages m2
                   WHERE m2.id = (
                       SELECT cp2.last_read_message_id 
                       FROM chat_participants cp2
                       WHERE cp2.chat_id = $1 AND cp2.user_id = $2
                   )
                  ),
                  '1970-01-01'::timestamp
              )`,
          [chatRow.id, userId]
        );
        
        chats.push({
          id: chatRow.id,
          title: chatRow.title || 'Чат',
          description: chatRow.description,
          created_at: chatRow.created_at,
          is_private: chatRow.is_private,
          is_pinned: chatRow.is_pinned,
          is_muted: chatRow.is_muted,
          is_channel: chatRow.is_channel,
          last_message: lastMessageResult.rows[0]?.text || null,
          last_message_time: lastMessageResult.rows[0]?.created_at || null,
          last_message_sender: lastMessageResult.rows[0]?.user_id || null,
          unread_count: parseInt(unreadResult.rows[0]?.count) || 0,
          participants: chatRow.participants || []
        });
      }
    }
    
    const result = {
      ...folder,
      chats: chats,
      chat_count: chatIds.length
    };
    
    await client.query('COMMIT');
    
    res.status(201).json({
      success: true,
      folder: result
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('🚨 Create folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка создания папки',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  } finally {
    client.release();
  }
});

// 63. GET Получить все папки пользователя
app.get('/api/folders', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    const foldersResult = await pool.query(
      `SELECT 
          f.id, f.name, f.avatar_color, f.avatar_url, f.user_id, 
          f.created_at, f.updated_at
       FROM folders f
       WHERE f.user_id = $1
       ORDER BY f.created_at DESC`,
      [userId]
    );
    
    const folders = [];
    
    for (const folder of foldersResult.rows) {
      const chatsResult = await pool.query(
        `SELECT c.id
         FROM folder_chats fc
         INNER JOIN chats c ON fc.chat_id = c.id
         WHERE fc.folder_id = $1`,
        [folder.id]
      );
      
      const chatIds = chatsResult.rows.map(row => row.id);
      let chats = [];
      
      if (chatIds.length > 0) {
        const placeholders = chatIds.map((_, i) => `$${i + 1}`).join(',');
        const chatQuery = `
          SELECT 
              c.id,
              c.title,
              c.description,
              c.created_at,
              c.is_private,
              c.is_pinned,
              c.is_muted,
              c.is_channel,
              (
                  SELECT json_agg(user_id)
                  FROM chat_participants cp
                  WHERE cp.chat_id = c.id
              ) as participants
           FROM chats c
           WHERE c.id IN (${placeholders})
        `;
        
        const detailedChats = await pool.query(chatQuery, chatIds);
        
        for (const chatRow of detailedChats.rows) {
          const lastMessageResult = await pool.query(
            `SELECT m.text, m.created_at, m.user_id
             FROM messages m
             WHERE m.chat_id = $1
             ORDER BY m.created_at DESC
             LIMIT 1`,
            [chatRow.id]
          );
          
          const unreadResult = await pool.query(
            `SELECT COUNT(*) as count
             FROM messages m
             WHERE m.chat_id = $1 
                AND m.user_id != $2
                AND m.created_at > COALESCE(
                    (SELECT m2.created_at 
                     FROM messages m2
                     WHERE m2.id = (
                         SELECT cp2.last_read_message_id 
                         FROM chat_participants cp2
                         WHERE cp2.chat_id = $1 AND cp2.user_id = $2
                     )
                    ),
                    '1970-01-01'::timestamp
                )`,
            [chatRow.id, userId]
          );
          
          chats.push({
            id: chatRow.id,
            title: chatRow.title || 'Чат',
            description: chatRow.description,
            created_at: chatRow.created_at,
            is_private: chatRow.is_private,
            is_pinned: chatRow.is_pinned,
            is_muted: chatRow.is_muted,
            is_channel: chatRow.is_channel,
            last_message: lastMessageResult.rows[0]?.text || null,
            last_message_time: lastMessageResult.rows[0]?.created_at || null,
            last_message_sender: lastMessageResult.rows[0]?.user_id || null,
            unread_count: parseInt(unreadResult.rows[0]?.count) || 0,
            participants: chatRow.participants || []
          });
        }
      }
      
      folders.push({
        ...folder,
        chats: chats,
        chat_count: chatIds.length
      });
    }
    
    res.json({
      success: true,
      folders: folders
    });
    
  } catch (error) {
    console.error('🚨 Get folders error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка получения папок',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 64. GET Получить конкретную папку
app.get('/api/folders/:id', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const folderId = parseInt(req.params.id);
    
    if (isNaN(folderId) || folderId <= 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Неверный ID папки' 
      });
    }
    
    const folderResult = await pool.query(
      `SELECT 
          f.id, f.name, f.avatar_color, f.avatar_url, f.user_id, 
          f.created_at, f.updated_at
       FROM folders f
       WHERE f.id = $1 AND f.user_id = $2`,
      [folderId, userId]
    );
    
    if (folderResult.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Папка не найдена' 
      });
    }
    
    const folder = folderResult.rows[0];
    
    const chatsResult = await pool.query(
      `SELECT c.id
       FROM folder_chats fc
       INNER JOIN chats c ON fc.chat_id = c.id
       WHERE fc.folder_id = $1`,
      [folderId]
    );
    
    const chatIds = chatsResult.rows.map(row => row.id);
    let chats = [];
    
    if (chatIds.length > 0) {
      const placeholders = chatIds.map((_, i) => `$${i + 1}`).join(',');
      const chatQuery = `
        SELECT 
            c.id,
            c.title,
            c.description,
            c.created_at,
            c.is_private,
            c.is_pinned,
            c.is_muted,
            c.is_channel,
            (
                SELECT json_agg(user_id)
                FROM chat_participants cp
                WHERE cp.chat_id = c.id
            ) as participants
         FROM chats c
         WHERE c.id IN (${placeholders})
      `;
      
      const detailedChats = await pool.query(chatQuery, chatIds);
      
      for (const chatRow of detailedChats.rows) {
        const lastMessageResult = await pool.query(
          `SELECT m.text, m.created_at, m.user_id
           FROM messages m
           WHERE m.chat_id = $1
           ORDER BY m.created_at DESC
           LIMIT 1`,
          [chatRow.id]
        );
        
        const unreadResult = await pool.query(
          `SELECT COUNT(*) as count
           FROM messages m
           WHERE m.chat_id = $1 
              AND m.user_id != $2
              AND m.created_at > COALESCE(
                  (SELECT m2.created_at 
                   FROM messages m2
                   WHERE m2.id = (
                       SELECT cp2.last_read_message_id 
                       FROM chat_participants cp2
                       WHERE cp2.chat_id = $1 AND cp2.user_id = $2
                   )
                  ),
                  '1970-01-01'::timestamp
              )`,
          [chatRow.id, userId]
        );
        
        chats.push({
          id: chatRow.id,
          title: chatRow.title || 'Чат',
          description: chatRow.description,
          created_at: chatRow.created_at,
          is_private: chatRow.is_private,
          is_pinned: chatRow.is_pinned,
          is_muted: chatRow.is_muted,
          is_channel: chatRow.is_channel,
          last_message: lastMessageResult.rows[0]?.text || null,
          last_message_time: lastMessageResult.rows[0]?.created_at || null,
          last_message_sender: lastMessageResult.rows[0]?.user_id || null,
          unread_count: parseInt(unreadResult.rows[0]?.count) || 0,
          participants: chatRow.participants || []
        });
      }
      
      chats.sort((a, b) => {
        const timeA = a.last_message_time ? new Date(a.last_message_time) : new Date(0);
        const timeB = b.last_message_time ? new Date(b.last_message_time) : new Date(0);
        return timeB - timeA;
      });
    }
    
    const result = {
      ...folder,
      chats: chats,
      chat_count: chatIds.length
    };
    
    res.json({
      success: true,
      folder: result
    });
    
  } catch (error) {
    console.error('🚨 Get folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка получения папки',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 65. PUT Обновить папку
app.put('/api/folders/:id', authMiddleware, uploadAvatar.single('avatar'), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const userId = req.user.userId;
    const folderId = parseInt(req.params.id);
    const { name, avatar_color, chat_ids } = req.body;
    
    console.log('📁 Update folder request:', {
      folderId,
      userId,
      name,
      avatar_color,
      chat_ids: chat_ids ? JSON.parse(chat_ids) : [],
      hasFile: !!req.file
    });
    
    if (isNaN(folderId) || folderId <= 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ 
        success: false, 
        error: 'Неверный ID папки' 
      });
    }
    
    const folderCheck = await client.query(
      'SELECT id FROM folders WHERE id = $1 AND user_id = $2',
      [folderId, userId]
    );
    
    if (folderCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ 
        success: false, 
        error: 'Папка не найдена' 
      });
    }
    
    const trimmedName = name ? name.trim() : '';
    
    if (trimmedName) {
      const existingFolder = await client.query(
        'SELECT id FROM folders WHERE name = $1 AND user_id = $2 AND id != $3',
        [trimmedName, userId, folderId]
      );
      
      if (existingFolder.rows.length > 0) {
        await client.query('ROLLBACK');
        return res.status(409).json({ 
          success: false, 
          error: 'Папка с таким названием уже существует' 
        });
      }
    }
    
    let avatarUrl = null;
    if (req.file) {
      try {
        const buffer = req.file.buffer;
        
        if (buffer.length < 100) {
          await client.query('ROLLBACK');
          return res.status(400).json({ 
            success: false, 
            error: 'Изображение слишком маленькое' 
          });
        }
        
        avatarUrl = await uploadToS3Avatar(buffer);
        
      } catch (error) {
        console.error('🚨 Avatar upload failed:', error.message);
        await client.query('ROLLBACK');
        return res.status(400).json({ 
          success: false,
          error: 'Ошибка загрузки аватара',
          details: error.message 
        });
      }
    }
    
    const updateFields = [];
    const queryParams = [];
    let paramIndex = 1;
    
    if (trimmedName) {
      updateFields.push(`name = $${paramIndex++}`);
      queryParams.push(trimmedName);
    }
    
    if (avatar_color) {
      updateFields.push(`avatar_color = $${paramIndex++}`);
      queryParams.push(avatar_color);
    }
    
    if (avatarUrl) {
      updateFields.push(`avatar_url = $${paramIndex++}`);
      queryParams.push(avatarUrl);
    }
    
    updateFields.push(`updated_at = NOW()`);
    
    queryParams.push(folderId);
    queryParams.push(userId);
    
    const query = `
      UPDATE folders 
      SET ${updateFields.join(', ')}
      WHERE id = $${paramIndex++} AND user_id = $${paramIndex}
      RETURNING id, name, avatar_color, avatar_url, user_id, created_at, updated_at`;
    
    const updateResult = await client.query(query, queryParams);
    
    if (chat_ids) {
      try {
        const chatIdsArray = JSON.parse(chat_ids);
        
        await client.query(
          'DELETE FROM folder_chats WHERE folder_id = $1',
          [folderId]
        );
        
        if (Array.isArray(chatIdsArray) && chatIdsArray.length > 0) {
          const validChatIds = [];
          for (const chatId of chatIdsArray) {
            const participantCheck = await client.query(
              'SELECT id FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
              [chatId, userId]
            );
            
            if (participantCheck.rows.length > 0) {
              validChatIds.push(chatId);
            }
          }
          
          if (validChatIds.length > 0) {
            for (const chatId of validChatIds) {
              await client.query(
                `INSERT INTO folder_chats (folder_id, chat_id, added_at)
                 VALUES ($1, $2, NOW())`,
                [folderId, chatId]
              );
            }
          }
        }
      } catch (parseError) {
        console.error('Error parsing chat_ids:', parseError);
      }
    }
    
    const updatedFolder = await client.query(
      `SELECT 
          f.id, f.name, f.avatar_color, f.avatar_url, f.user_id, 
          f.created_at, f.updated_at
       FROM folders f
       WHERE f.id = $1 AND f.user_id = $2`,
      [folderId, userId]
    );
    
    if (updatedFolder.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(500).json({ 
        success: false, 
        error: 'Ошибка получения обновленной папки' 
      });
    }
    
    const folder = updatedFolder.rows[0];
    
    const chatsResult = await client.query(
      `SELECT c.id
       FROM folder_chats fc
       INNER JOIN chats c ON fc.chat_id = c.id
       WHERE fc.folder_id = $1`,
      [folderId]
    );
    
    const chatIds = chatsResult.rows.map(row => row.id);
    let chats = [];
    
    if (chatIds.length > 0) {
      const placeholders = chatIds.map((_, i) => `$${i + 1}`).join(',');
      const chatQuery = `
        SELECT 
            c.id,
            c.title,
            c.description,
            c.created_at,
            c.is_private,
            c.is_pinned,
            c.is_muted,
            c.is_channel,
            (
                SELECT json_agg(user_id)
                FROM chat_participants cp
                WHERE cp.chat_id = c.id
            ) as participants
         FROM chats c
         WHERE c.id IN (${placeholders})
      `;
      
      const detailedChats = await client.query(chatQuery, chatIds);
      
      for (const chatRow of detailedChats.rows) {
        const lastMessageResult = await client.query(
          `SELECT m.text, m.created_at, m.user_id
           FROM messages m
           WHERE m.chat_id = $1
           ORDER BY m.created_at DESC
           LIMIT 1`,
          [chatRow.id]
        );
        
        const unreadResult = await client.query(
          `SELECT COUNT(*) as count
           FROM messages m
           WHERE m.chat_id = $1 
              AND m.user_id != $2
              AND m.created_at > COALESCE(
                  (SELECT m2.created_at 
                   FROM messages m2
                   WHERE m2.id = (
                       SELECT cp2.last_read_message_id 
                       FROM chat_participants cp2
                       WHERE cp2.chat_id = $1 AND cp2.user_id = $2
                   )
                  ),
                  '1970-01-01'::timestamp
              )`,
          [chatRow.id, userId]
        );
        
        chats.push({
          id: chatRow.id,
          title: chatRow.title || 'Чат',
          description: chatRow.description,
          created_at: chatRow.created_at,
          is_private: chatRow.is_private,
          is_pinned: chatRow.is_pinned,
          is_muted: chatRow.is_muted,
          is_channel: chatRow.is_channel,
          last_message: lastMessageResult.rows[0]?.text || null,
          last_message_time: lastMessageResult.rows[0]?.created_at || null,
          last_message_sender: lastMessageResult.rows[0]?.user_id || null,
          unread_count: parseInt(unreadResult.rows[0]?.count) || 0,
          participants: chatRow.participants || []
        });
      }
      
      chats.sort((a, b) => {
        const timeA = a.last_message_time ? new Date(a.last_message_time) : new Date(0);
        const timeB = b.last_message_time ? new Date(b.last_message_time) : new Date(0);
        return timeB - timeA;
      });
    }
    
    const result = {
      ...folder,
      chats: chats,
      chat_count: chatIds.length
    };
    
    await client.query('COMMIT');
    
    res.json({
      success: true,
      folder: result
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('🚨 Update folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка обновления папки',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  } finally {
    client.release();
  }
});

// 66. DELETE Удалить папку
app.delete('/api/folders/:id', authMiddleware, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const userId = req.user.userId;
    const folderId = parseInt(req.params.id);
    
    if (isNaN(folderId) || folderId <= 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ 
        success: false, 
        error: 'Неверный ID папки' 
      });
    }
    
    const folderCheck = await client.query(
      'SELECT id FROM folders WHERE id = $1 AND user_id = $2',
      [folderId, userId]
    );
    
    if (folderCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ 
        success: false, 
        error: 'Папка не найдена' 
      });
    }
    
    await client.query(
      'DELETE FROM folder_chats WHERE folder_id = $1',
      [folderId]
    );
    
    await client.query(
      'DELETE FROM folders WHERE id = $1',
      [folderId]
    );
    
    await client.query('COMMIT');
    
    res.json({
      success: true,
      message: 'Папка успешно удалена'
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('🚨 Delete folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка удаления папки',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  } finally {
    client.release();
  }
});

// 67. POST Добавить чат в папку
app.post('/api/folders/:folderId/chats/:chatId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const folderId = parseInt(req.params.folderId);
    const chatId = parseInt(req.params.chatId);
    
    console.log('📁 Add chat to folder:', { userId, folderId, chatId });
    
    if (isNaN(folderId) || folderId <= 0 || isNaN(chatId) || chatId <= 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Неверные параметры' 
      });
    }
    
    const folderCheck = await pool.query(
      'SELECT id FROM folders WHERE id = $1 AND user_id = $2',
      [folderId, userId]
    );
    
    if (folderCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Папка не найдена' 
      });
    }
    
    const participantCheck = await pool.query(
      'SELECT id FROM chat_participants WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (participantCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Вы не являетесь участником этого чата' 
      });
    }
    
    const existingLink = await pool.query(
      'SELECT id FROM folder_chats WHERE folder_id = $1 AND chat_id = $2',
      [folderId, chatId]
    );
    
    if (existingLink.rows.length > 0) {
      return res.status(409).json({ 
        success: false, 
        error: 'Чат уже добавлен в эту папку' 
      });
    }
    
    await pool.query(
      'INSERT INTO folder_chats (folder_id, chat_id, added_at) VALUES ($1, $2, NOW())',
      [folderId, chatId]
    );
    
    res.json({
      success: true,
      message: 'Чат успешно добавлен в папку'
    });
    
  } catch (error) {
    console.error('🚨 Add chat to folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка добавления чата в папку',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 68. DELETE Удалить чат из папки
app.delete('/api/folders/:folderId/chats/:chatId', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    const folderId = parseInt(req.params.folderId);
    const chatId = parseInt(req.params.chatId);
    
    console.log('📁 Remove chat from folder:', { userId, folderId, chatId });
    
    if (isNaN(folderId) || folderId <= 0 || isNaN(chatId) || chatId <= 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Неверные параметры' 
      });
    }
    
    const folderCheck = await pool.query(
      'SELECT id FROM folders WHERE id = $1 AND user_id = $2',
      [folderId, userId]
    );
    
    if (folderCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Папка не найдена' 
      });
    }
    
    const deleteResult = await pool.query(
      'DELETE FROM folder_chats WHERE folder_id = $1 AND chat_id = $2 RETURNING id',
      [folderId, chatId]
    );
    
    if (deleteResult.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Чат не найден в этой папке' 
      });
    }
    
    res.json({
      success: true,
      message: 'Чат успешно удален из папки'
    });
    
  } catch (error) {
    console.error('🚨 Remove chat from folder error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка удаления чата из папки',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// 69. POST Создать комнату для звонка
app.post('/api/calls/create', authMiddleware, async (req, res) => {
  try {
    const { chat_id, recipient_id, is_video_call } = req.body;
    const caller_id = req.user.userId;
    const caller_email = req.user.email;
    const caller_name = caller_email ? caller_email.split('@')[0] : `User ${caller_id}`;

    console.log('📞 Create call request:', {
      chat_id,
      caller_id,
      recipient_id,
      is_video_call,
      caller_name
    });

    if (!chat_id || !recipient_id) {
      return res.status(400).json({
        success: false,
        message: 'Необходимые поля: chat_id, recipient_id'
      });
    }

    const activeCall = await pool.query(
      `SELECT room_id FROM active_calls 
       WHERE (caller_id = $1 OR recipient_id = $1) 
       AND status NOT IN ('ended', 'rejected', 'failed')`,
      [caller_id]
    );

    if (activeCall.rows.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Вы уже участвуете в другом звонке',
        room_id: activeCall.rows[0].room_id
      });
    }

    const recipientCheck = await pool.query(
      'SELECT email_encrypted, name FROM users WHERE id = $1',
      [recipient_id]
    );

    if (recipientCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Получатель не найден'
      });
    }

    let recipient_name = `User ${recipient_id}`;
    const recipient_email = decryptString(recipientCheck.rows[0].email_encrypted);
    if (recipient_email) {
      recipient_name = recipient_email.split('@')[0];
    }

    const room_id = `call_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    const userCheck = await pool.query(
      'SELECT email_encrypted FROM users WHERE id = $1',
      [caller_id]
    );

    let janus_session_id = null;
    let janus_handle_id = null;
    let janus_room_id = null;

    try {
      const sessionResponse = await axios.post(
        `${JANUS_ADMIN_URL}/janus`,
        {
          janus: 'create',
          transaction: generateTransactionId(),
        },
        {
          timeout: 10000,
          headers: { 'Content-Type': 'application/json' },
        }
      );

      if (sessionResponse.data.janus !== 'success') {
        throw new Error('Failed to create Janus session');
      }

      janus_session_id = sessionResponse.data.data.id;

      const pluginResponse = await axios.post(
        `${JANUS_ADMIN_URL}/janus/${janus_session_id}`,
        {
          janus: 'attach',
          plugin: 'janus.plugin.videoroom',
          transaction: generateTransactionId(),
        },
        { timeout: 10000 }
      );

      if (pluginResponse.data.janus !== 'success') {
        throw new Error('Failed to attach to Janus plugin');
      }

      janus_handle_id = pluginResponse.data.data.id;

      janus_room_id = Math.floor(Math.random() * 1000000);
      
      const roomResponse = await axios.post(
        `${JANUS_ADMIN_URL}/janus/${janus_session_id}/${janus_handle_id}`,
        {
          janus: 'message',
          body: {
            request: 'create',
            room: janus_room_id,
            description: `Chat ${chat_id}`,
            is_private: true,
            publishers: 2,
            bitrate: is_video_call ? 512000 : 64000,
            audiocodec: 'opus',
            videocodec: is_video_call ? 'vp8' : null,
            record: false,
            lock_record: true,
          },
          transaction: generateTransactionId(),
        },
        { timeout: 10000 }
      );

      if (roomResponse.data.janus !== 'ack') {
        throw new Error('Failed to create Janus room');
      }

    } catch (janusError) {
      console.error('❌ Janus error:', janusError.message);
      
      if (janus_session_id && janus_handle_id) {
        await cleanupJanusResources(janus_session_id, janus_handle_id, janus_room_id);
      }
      
      return res.status(500).json({
        success: false,
        message: 'Ошибка создания звонка (Janus)',
        details: janusError.message
      });
    }

    const result = await pool.query(
      `INSERT INTO call_rooms 
       (room_id, chat_id, caller_id, recipient_id, caller_name, recipient_name,
        is_video_call, janus_session_id, janus_handle_id, 
        janus_room_id, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING id, created_at`,
      [
        room_id,
        chat_id,
        caller_id,
        recipient_id,
        caller_name,
        recipient_name,
        is_video_call || false,
        janus_session_id,
        janus_handle_id,
        janus_room_id,
        'ringing',
        new Date().toISOString()
      ]
    );

    await pool.query(
      `INSERT INTO active_calls 
       (room_id, chat_id, caller_id, recipient_id, status, started_at)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [room_id, chat_id, caller_id, recipient_id, 'ringing', new Date().toISOString()]
    );

    const token = generateJanusToken(caller_id, room_id);

    console.log(`✅ Создана комната для звонка ${room_id} в чате ${chat_id}`);

    res.json({
      success: true,
      message: 'Комната для звонка создана',
      room: {
        id: room_id,
        chat_id,
        caller_id,
        recipient_id,
        caller_name,
        recipient_name,
        is_video_call: is_video_call || false,
        created_at: result.rows[0].created_at,
        status: 'ringing'
      },
      janus_config: {
        server_url: `${JANUS_WS_URL}/janus`,
        room_id: janus_room_id,
        session_id: janus_session_id,
        handle_id: janus_handle_id,
        token,
        is_publisher: true,
        ice_servers: getIceServers(),
        audio_config: {
          codec: 'opus',
          bitrate: 64000,
          stereo: false,
          fec: true
        },
        video_config: is_video_call ? {
          codec: 'vp8',
          bitrate: 512000,
          width: 640,
          height: 480,
          fps: 30
        } : null
      }
    });

  } catch (error) {
    console.error('❌ Error creating call room:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка создания комнаты для звонка',
      error: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// 70. GET Получить информацию о комнате
app.get('/api/calls/room/:room_id', authMiddleware, async (req, res) => {
  try {
    const { room_id } = req.params;
    const user_id = req.user.userId;

    console.log('📞 Get room info:', { room_id, user_id });

    const result = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE room_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)`,
      [room_id, user_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Комната не найдена или доступ запрещен'
      });
    }

    const room = result.rows[0];

    res.json({
      success: true,
      message: 'Информация о комнате',
      room: {
        id: room.room_id,
        chat_id: room.chat_id,
        caller_id: room.caller_id,
        recipient_id: room.recipient_id,
        caller_name: room.caller_name,
        recipient_name: room.recipient_name,
        is_video_call: room.is_video_call,
        created_at: room.created_at,
        status: room.status,
        ended_at: room.ended_at,
        end_reason: room.end_reason
      }
    });

  } catch (error) {
    console.error('❌ Error getting call room:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка получения информации о комнате',
      error: error.message
    });
  }
});

// 71. POST Подключиться к комнате (для получателя)
app.post('/api/calls/room/:room_id/join', authMiddleware, async (req, res) => {
  try {
    const { room_id } = req.params;
    const user_id = req.user.userId;
    const user_email = req.user.email;
    const user_name = user_email ? user_email.split('@')[0] : `User ${user_id}`;

    console.log('📞 Join room:', { room_id, user_id, user_name });

    const roomResult = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE room_id = $1 AND recipient_id = $2 AND status = 'ringing'`,
      [room_id, user_id]
    );

    if (roomResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Комната не найдена или звонок уже завершен'
      });
    }

    const room = roomResult.rows[0];

    const activeCall = await pool.query(
      `SELECT room_id FROM active_calls 
       WHERE (caller_id = $1 OR recipient_id = $1) 
       AND status NOT IN ('ended', 'rejected', 'failed')`,
      [user_id]
    );

    if (activeCall.rows.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Вы уже участвуете в другом звонке'
      });
    }

    await pool.query(
      `UPDATE call_rooms SET status = 'in_progress', updated_at = $1 
       WHERE room_id = $2`,
      [new Date().toISOString(), room_id]
    );

    await pool.query(
      `UPDATE active_calls SET status = 'in_progress' 
       WHERE room_id = $1`,
      [room_id]
    );

    const token = generateJanusToken(user_id, room_id);

    console.log(`✅ Пользователь ${user_id} присоединился к звонку ${room_id}`);

    res.json({
      success: true,
      message: 'Вы подключились к звонку',
      janus_config: {
        server_url: `${JANUS_WS_URL}/janus`,
        room_id: room.janus_room_id,
        session_id: room.janus_session_id,
        handle_id: room.janus_handle_id,
        token,
        is_publisher: false,
        display_name: user_name,
        ice_servers: getIceServers(),
        audio_config: {
          codec: 'opus',
          bitrate: 64000,
          stereo: false,
          fec: true
        },
        video_config: room.is_video_call ? {
          codec: 'vp8',
          bitrate: 512000,
          width: 640,
          height: 480,
          fps: 30
        } : null
      }
    });

  } catch (error) {
    console.error('❌ Error joining call room:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка подключения к звонку',
      error: error.message
    });
  }
});

// 72. GET Получить конфигурацию Janus для комнаты
app.get('/api/calls/room/:room_id/janus-config', authMiddleware, async (req, res) => {
  try {
    const { room_id } = req.params;
    const user_id = req.user.userId;
    const user_email = req.user.email;
    const user_name = user_email ? user_email.split('@')[0] : `User ${user_id}`;

    console.log('📞 Get Janus config:', { room_id, user_id });

    const result = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE room_id = $1 
       AND (caller_id = $2 OR recipient_id = $2) 
       AND status IN ('ringing', 'in_progress')`,
      [room_id, user_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Комната не найдена или доступ запрещен'
      });
    }

    const room = result.rows[0];
    const is_publisher = room.caller_id === user_id;
    
    const token = generateJanusToken(user_id, room_id);

    res.json({
      success: true,
      message: 'Конфигурация Janus',
      janus_config: {
        server_url: `${JANUS_WS_URL}/janus`,
        room_id: room.janus_room_id,
        session_id: room.janus_session_id,
        handle_id: room.janus_handle_id,
        token,
        is_publisher,
        display_name: user_name,
        ice_servers: getIceServers(),
        audio_config: {
          codec: 'opus',
          bitrate: 64000,
          stereo: false,
          fec: true
        },
        video_config: room.is_video_call ? {
          codec: 'vp8',
          bitrate: 512000,
          width: 640,
          height: 480,
          fps: 30
        } : null
      }
    });

  } catch (error) {
    console.error('❌ Error getting Janus config:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка получения конфигурации Janus',
      error: error.message
    });
  }
});

// 73. PUT Обновить статус звонка
app.put('/api/calls/room/:room_id/status', authMiddleware, async (req, res) => {
  try {
    const { room_id } = req.params;
    const { status, reason } = req.body;
    const user_id = req.user.userId;

    console.log('📞 Update call status:', { room_id, user_id, status, reason });

    const roomResult = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE room_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)`,
      [room_id, user_id]
    );

    if (roomResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Комната не найдена или доступ запрещен'
      });
    }

    const room = roomResult.rows[0];

    await pool.query(
      `UPDATE call_rooms 
       SET status = $1, end_reason = $2, updated_at = $3, ended_at = $4
       WHERE room_id = $5`,
      [
        status,
        reason || null,
        new Date().toISOString(),
        ['ended', 'rejected', 'failed', 'missed'].includes(status) 
          ? new Date().toISOString() 
          : null,
        room_id
      ]
    );

    if (['ended', 'rejected', 'failed', 'missed'].includes(status)) {
      await pool.query(
        `DELETE FROM active_calls WHERE room_id = $1`,
        [room_id]
      );

      await cleanupJanusResources(
        room.janus_session_id,
        room.janus_handle_id,
        room.janus_room_id
      );

      console.log(`✅ Звонок ${room_id} завершен со статусом: ${status}`);
    }

    res.json({
      success: true,
      message: `Статус звонка обновлен на: ${status}`,
      room_id,
      status,
      updated_at: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Error updating call status:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка обновления статуса звонка',
      error: error.message
    });
  }
});

// 74. DELETE Завершить звонок
app.delete('/api/calls/room/:room_id', authMiddleware, async (req, res) => {
  try {
    const { room_id } = req.params;
    const { reason } = req.body;
    const user_id = req.user.userId;

    console.log('📞 End call:', { room_id, user_id, reason });

    const roomResult = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE room_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)`,
      [room_id, user_id]
    );

    if (roomResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Комната не найдена или доступ запрещен'
      });
    }

    const room = roomResult.rows[0];

    await pool.query(
      `UPDATE call_rooms 
       SET status = 'ended', end_reason = $1, 
           updated_at = $2, ended_at = $3
       WHERE room_id = $4`,
      [
        reason || 'ended_by_user',
        new Date().toISOString(),
        new Date().toISOString(),
        room_id
      ]
    );

    await pool.query(
      `DELETE FROM active_calls WHERE room_id = $1`,
      [room_id]
    );

    await cleanupJanusResources(
      room.janus_session_id,
      room.janus_handle_id,
      room.janus_room_id
    );

    console.log(`✅ Звонок ${room_id} завершен пользователем ${user_id}`);

    res.json({
      success: true,
      message: 'Звонок завершен',
      room_id,
      ended_at: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Error ending call:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка завершения звонка',
      error: error.message
    });
  }
});

// 75. GET Получить активные звонки пользователя
app.get('/api/calls/active', authMiddleware, async (req, res) => {
  try {
    const user_id = req.user.userId;

    console.log('📞 Get active calls:', { user_id });

    const result = await pool.query(
      `SELECT cr.* 
       FROM call_rooms cr
       WHERE (cr.caller_id = $1 OR cr.recipient_id = $1)
       AND cr.status IN ('ringing', 'in_progress')
       ORDER BY cr.created_at DESC`,
      [user_id]
    );

    res.json({
      success: true,
      message: 'Активные звонки',
      calls: result.rows.map(room => ({
        id: room.room_id,
        chat_id: room.chat_id,
        caller_id: room.caller_id,
        recipient_id: room.recipient_id,
        caller_name: room.caller_name,
        recipient_name: room.recipient_name,
        is_video_call: room.is_video_call,
        created_at: room.created_at,
        status: room.status
      })),
      count: result.rows.length
    });

  } catch (error) {
    console.error('❌ Error getting active calls:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка получения активных звонков',
      error: error.message
    });
  }
});

// 76. GET История звонков в чате
app.get('/api/calls/history/:chat_id', authMiddleware, async (req, res) => {
  try {
    const { chat_id } = req.params;
    const user_id = req.user.userId;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    console.log('📞 Get call history for chat:', { chat_id, user_id, page, limit });

    const chatCheck = await pool.query(
      `SELECT 1 FROM chat_participants 
       WHERE chat_id = $1 AND user_id = $2`,
      [chat_id, user_id]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({
        success: false,
        message: 'Нет доступа к этому чату'
      });
    }

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM call_rooms 
       WHERE chat_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)
       AND status IN ('ended', 'rejected', 'failed', 'missed')`,
      [chat_id, user_id]
    );

    const totalCount = parseInt(countResult.rows[0].total) || 0;

    const result = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE chat_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)
       AND status IN ('ended', 'rejected', 'failed', 'missed')
       ORDER BY created_at DESC
       LIMIT $3 OFFSET $4`,
      [chat_id, user_id, limit, offset]
    );

    const calls = result.rows.map(room => {
      const duration = room.ended_at ? 
        Math.floor((new Date(room.ended_at) - new Date(room.created_at)) / 1000) 
        : null;
      
      const call_type = room.is_video_call ? 'video' : 'audio';
      
      const direction = room.caller_id === user_id ? 'outgoing' : 'incoming';
      
      let call_status = 'completed';
      if (room.status === 'missed') {
        call_status = direction === 'incoming' ? 'missed' : 'not_answered';
      } else if (room.status === 'rejected') {
        call_status = 'rejected';
      } else if (room.status === 'failed') {
        call_status = 'failed';
      }

      return {
        id: room.room_id,
        chat_id: room.chat_id,
        caller_id: room.caller_id,
        recipient_id: room.recipient_id,
        caller_name: room.caller_name,
        recipient_name: room.recipient_name,
        is_video_call: room.is_video_call,
        call_type: call_type,
        direction: direction,
        status: call_status,
        created_at: room.created_at,
        ended_at: room.ended_at,
        end_reason: room.end_reason,
        duration: duration,
        duration_formatted: duration ? formatDuration(duration) : null,
        janus_room_id: room.janus_room_id
      };
    });

    res.json({
      success: true,
      message: 'История звонков чата',
      chat_id: parseInt(chat_id),
      calls: calls,
      pagination: {
        current_page: page,
        total_pages: Math.ceil(totalCount / limit),
        total_items: totalCount,
        items_per_page: limit,
        has_more: page * limit < totalCount
      }
    });

  } catch (error) {
    console.error('❌ Error getting call history for chat:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка получения истории звонков чата',
      error: error.message
    });
  }
});

// 77. GET Ping эндпоинт
app.get('/api/calls/ping', authMiddleware, async (req, res) => {
  try {
    const user_id = req.user.userId;
    const user_email = req.user.email;
    
    const janusAlive = await checkJanusConnection();
    
    res.json({
      success: true,
      message: 'Calls API is working',
      timestamp: new Date().toISOString(),
      user: {
        id: user_id,
        email: user_email
      },
      janus: {
        connected: janusAlive,
        admin_url: JANUS_ADMIN_URL,
        ws_url: JANUS_WS_URL
      }
    });

  } catch (error) {
    console.error('❌ Ping error:', error);
    res.status(500).json({
      success: false,
      message: 'Calls API error',
      error: error.message
    });
  }
});

// 78. GET Список всех звонков
app.get('/api/calls/history', authMiddleware, async (req, res) => {
  try {
    const user_id = req.user.userId;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    console.log('📞 Get call history (all):', { user_id, page, limit });

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM call_rooms 
       WHERE (caller_id = $1 OR recipient_id = $1)
       AND status IN ('ended', 'rejected', 'failed', 'missed')`,
      [user_id]
    );

    const totalCount = parseInt(countResult.rows[0].total) || 0;

    const result = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE (caller_id = $1 OR recipient_id = $1)
       AND status IN ('ended', 'rejected', 'failed', 'missed')
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [user_id, limit, offset]
    );

    const calls = result.rows.map(room => {
      const duration = room.ended_at ? 
        Math.floor((new Date(room.ended_at) - new Date(room.created_at)) / 1000) 
        : null;
      
      const call_type = room.is_video_call ? 'video' : 'audio';
      
      const direction = room.caller_id === user_id ? 'outgoing' : 'incoming';
      
      let call_status = 'completed';
      if (room.status === 'missed') {
        call_status = direction === 'incoming' ? 'missed' : 'not_answered';
      } else if (room.status === 'rejected') {
        call_status = 'rejected';
      } else if (room.status === 'failed') {
        call_status = 'failed';
      }

      return {
        id: room.room_id,
        chat_id: room.chat_id,
        caller_id: room.caller_id,
        recipient_id: room.recipient_id,
        caller_name: room.caller_name,
        recipient_name: room.recipient_name,
        is_video_call: room.is_video_call,
        call_type: call_type,
        direction: direction,
        status: call_status,
        created_at: room.created_at,
        ended_at: room.ended_at,
        end_reason: room.end_reason,
        duration: duration,
        duration_formatted: duration ? formatDuration(duration) : null
      };
    });

    res.json({
      success: true,
      message: 'Общая история звонков',
      calls: calls,
      pagination: {
        current_page: page,
        total_pages: Math.ceil(totalCount / limit),
        total_items: totalCount,
        items_per_page: limit,
        has_more: page * limit < totalCount
      }
    });

  } catch (error) {
    console.error('❌ Error getting call history (all):', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка получения истории звонков',
      error: error.message
    });
  }
});

// 78. GET Проверить есть ли активный звонок в чате
app.get('/api/calls/active/:chat_id', authMiddleware, async (req, res) => {
  try {
    const { chat_id } = req.params;
    const user_id = req.user.userId;

    console.log('📞 Check active call in chat:', { chat_id, user_id });

    const result = await pool.query(
      `SELECT * FROM call_rooms 
       WHERE chat_id = $1 
       AND (caller_id = $2 OR recipient_id = $2)
       AND status IN ('ringing', 'in_progress')
       LIMIT 1`,
      [chat_id, user_id]
    );

    if (result.rows.length === 0) {
      return res.json({
        success: true,
        has_active_call: false,
        message: 'Нет активных звонков в этом чате'
      });
    }

    const room = result.rows[0];
    const is_caller = room.caller_id === user_id;

    res.json({
      success: true,
      has_active_call: true,
      message: 'В чате есть активный звонок',
      call: {
        id: room.room_id,
        chat_id: room.chat_id,
        caller_id: room.caller_id,
        recipient_id: room.recipient_id,
        caller_name: room.caller_name,
        recipient_name: room.recipient_name,
        is_video_call: room.is_video_call,
        created_at: room.created_at,
        status: room.status,
        is_caller: is_caller,
        is_recipient: !is_caller,
        can_join: !is_caller && room.status === 'ringing'
      }
    });

  } catch (error) {
    console.error('❌ Error checking active call:', error);
    res.status(500).json({
      success: false,
      message: 'Ошибка проверки активного звонка',
      error: error.message
    });
  }
});

// 79. Эндпоинт перенаправляющий на внешние API
app.all('/api/proxy', authMiddleware, async (req, res) => {
  try {
    const { url } = req.query;
    
    if (!url) {
      return res.status(400).json({ 
        success: false, 
        error: 'Не указан целевой URL' 
      });
    }

    const targetUrl = decodeURIComponent(url);
    
    const allowedDomains = [
      'www.cbr-xml-daily.ru',
      'cbr-xml-daily.ru',
      'v2.jokeapi.dev',
      'restcountries.com',
      'api.binance.com',
      'api.quotable.io',
      'dog.ceo',
      'api.thecatapi.com',
      'api.frankfurter.app',
      'api.open-meteo.com',    
      'geocoding-api.open-meteo.com'
    ];

    const urlObj = new URL(targetUrl);
    const isAllowed = allowedDomains.some(domain => 
      urlObj.hostname === domain || urlObj.hostname.endsWith('.' + domain)
    );

    if (!isAllowed) {
      console.warn(`⚠️ Заблокирован запрос к неразрешенному домену: ${urlObj.hostname}`);
      return res.status(403).json({
        success: false,
        error: 'Домен не разрешен'
      });
    }

    console.log(`🌐 Прокси запрос к: ${targetUrl}`);

    const headers = {
      'User-Agent': 'Mozilla/5.0 (compatible; SaferChatProxy/1.0)',
      'Accept': 'application/json, text/plain, */*',
    };

    if (req.headers['accept-language']) {
      headers['Accept-Language'] = req.headers['accept-language'];
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);

    const response = await fetch(targetUrl, {
      method: req.method,
      headers: headers,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    const contentType = response.headers.get('content-type') || '';
    let responseData;

    if (contentType.includes('application/json')) {
      responseData = await response.json();
    } else if (contentType.includes('text/')) {
      responseData = await response.text();
    } else {
      const buffer = await response.arrayBuffer();
      responseData = Buffer.from(buffer).toString('base64');
    }

    res.set('Cache-Control', 'public, max-age=1800');
    res.set('X-Proxy-Cache', 'MISS');
    
    res.status(response.status).json({
      success: true,
      status: response.status,
      contentType: contentType,
      data: responseData
    });

  } catch (error) {
    console.error('❌ Ошибка прокси:', error.message);
    
    res.status(500).json({
      success: false,
      error: 'Внешний сервис временно недоступен'
    });
  }
});

// 80. Создание новой группы
app.post('/api/groups', authMiddleware, uploadAvatar.single('avatar'), async (req, res) => {
  const client = await pool.connect();
  
  try {
    const { name, description, avatar_color, member_ids } = req.body;
    const userId = req.user.userId;
    
    console.log('👥 Создание группы:', {
      userId,
      name,
      description,
      avatar_color,
      member_ids: member_ids ? JSON.parse(member_ids) : []
    });

    if (!name || name.trim().length === 0) {
      return res.status(400).json({ error: 'Название группы обязательно' });
    }

    if (name.trim().length > 100) {
      return res.status(400).json({ error: 'Название группы не должно превышать 100 символов' });
    }

    await client.query('BEGIN');

    let avatarUrl = null;
    if (req.file) {
      try {
        avatarUrl = await uploadToS3Avatar(req.file.buffer);
      } catch (error) {
        console.error('❌ Avatar upload failed:', error.message);
        await client.query('ROLLBACK');
        return res.status(400).json({ 
          error: 'Ошибка загрузки аватара',
          details: error.message 
        });
      }
    }

    const insertGroupQuery = `
      INSERT INTO groups (name, description, avatar_url, avatar_color, created_by, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING id, name, description, avatar_url, avatar_color, created_by, created_at
    `;

    const groupResult = await client.query(insertGroupQuery, [
      name.trim(),
      description?.trim() || null,
      avatarUrl,
      avatar_color || '#2196F3',
      userId
    ]);

    const group = groupResult.rows[0];
    console.log(`✅ Группа ${group.id} создана пользователем ${userId}`);

    await client.query(
      'INSERT INTO group_members (group_id, user_id, role, joined_at) VALUES ($1, $2, $3, NOW())',
      [group.id, userId, 'admin']
    );

    let memberIdsArray = [];
    if (member_ids) {
      try {
        memberIdsArray = typeof member_ids === 'string' 
          ? JSON.parse(member_ids) 
          : member_ids;
      } catch (e) {
        console.error('Ошибка парсинга member_ids:', e);
      }
    }

    if (Array.isArray(memberIdsArray) && memberIdsArray.length > 0) {
      for (const memberId of memberIdsArray) {
        const userCheck = await client.query(
          'SELECT id FROM users WHERE id = $1',
          [memberId]
        );
        
        if (userCheck.rows.length > 0) {
          await client.query(
            'INSERT INTO group_members (group_id, user_id, role, joined_at) VALUES ($1, $2, $3, NOW())',
            [group.id, memberId, 'member']
          );
        }
      }
      console.log(`✅ Добавлено ${memberIdsArray.length} участников в группу ${group.id}`);
    }

    await client.query('COMMIT');

    res.status(201).json({
      success: true,
      message: 'Группа успешно создана',
      group: {
        ...group,
        members_count: 1 + (memberIdsArray.length || 0)
      }
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Ошибка создания группы:', error);
    res.status(500).json({ 
      error: 'Ошибка создания группы',
      details: error.message 
    });
  } finally {
    client.release();
  }
});

// 81. Получение информации о группе
app.get('/api/groups/:groupId', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    const result = await pool.query(`
      SELECT 
        g.*,
        COUNT(DISTINCT gm.user_id) as members_count,
        EXISTS(
          SELECT 1 FROM group_members 
          WHERE group_id = g.id AND user_id = $2
        ) as is_member
      FROM groups g
      LEFT JOIN group_members gm ON g.id = gm.group_id
      WHERE g.id = $1
      GROUP BY g.id
    `, [groupId, userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Группа не найдена' 
      });
    }

    res.json({ 
      success: true, 
      group: result.rows[0] 
    });
  } catch (error) {
    console.error('Ошибка получения информации о группе:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 82. Получение участников группы
app.get('/api/groups/:groupId/members', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    const memberCheck = await pool.query(
      'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не являетесь участником этой группы' 
      });
    }

    const result = await pool.query(`
      SELECT 
        u.id,
        u.nickname,
        u.name,
        u.avatar_url,
        u.avatar_color,
        gm.role,
        gm.joined_at
      FROM group_members gm
      JOIN users u ON gm.user_id = u.id
      WHERE gm.group_id = $1
      ORDER BY 
        CASE gm.role 
          WHEN 'admin' THEN 1 
          WHEN 'member' THEN 2 
          ELSE 3 
        END,
        gm.joined_at ASC
    `, [groupId]);

    const members = result.rows.map(member => {
      let displayName = 'Пользователь';
      const decryptedName = member.name ? decryptString(member.name) : null;
      const decryptedNickname = member.nickname ? decryptString(member.nickname) : null;
      
      displayName = decryptedNickname || decryptedName || `User ${member.id}`;
      
      return {
        id: member.id,
        display_name: displayName,
        nickname: decryptedNickname,
        name: decryptedName,
        avatar_url: member.avatar_url,
        avatar_color: member.avatar_color,
        role: member.role,
        joined_at: member.joined_at
      };
    });

    res.json({ 
      success: true, 
      members: members,
      count: members.length
    });
  } catch (error) {
    console.error('Ошибка получения участников группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 83. Получение сообщений группы
app.get('/api/groups/:groupId/messages', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  const page = parseInt(req.query.page) || 1;
  const limit = parseInt(req.query.limit) || 20;
  const offset = (page - 1) * limit;

  try {
    const memberCheck = await pool.query(
      'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не являетесь участником этой группы' 
      });
    }

    const messagesQuery = `
      SELECT 
        gm.id,
        gm.group_id,
        gm.user_id,
        gm.text,
        gm.file_url,
        gm.type_id,
        gm.duration,
        gm.created_at,
        gm.is_forwarded,
        gm.forwarded_from,
        u.nickname,
        u.name,
        u.avatar_url
      FROM group_messages gm
      JOIN users u ON gm.user_id = u.id
      WHERE gm.group_id = $1
      ORDER BY gm.created_at DESC
      LIMIT $2 OFFSET $3
    `;

    const result = await pool.query(messagesQuery, [groupId, limit, offset]);

    const countResult = await pool.query(
      'SELECT COUNT(*) FROM group_messages WHERE group_id = $1',
      [groupId]
    );

    const totalCount = parseInt(countResult.rows[0].count);

    const messages = result.rows.map(msg => {
      const decryptedName = msg.name ? decryptString(msg.name) : null;
      const decryptedNickname = msg.nickname ? decryptString(msg.nickname) : null;
      const senderName = decryptedNickname || decryptedName || `User ${msg.user_id}`;

      return {
        id: msg.id,
        group_id: msg.group_id,
        user_id: msg.user_id,
        text: msg.text ? decryptMessage(msg.text) : '',
        file_url: msg.file_url,
        type_id: msg.type_id,
        duration: msg.duration,
        created_at: msg.created_at,
        is_forwarded: msg.is_forwarded || false,
        forwarded_from: msg.forwarded_from,
        sender_name: senderName,
        sender_avatar: msg.avatar_url
      };
    }).reverse();

    res.json({
      success: true,
      messages: messages,
      pagination: {
        currentPage: page,
        totalPages: Math.ceil(totalCount / limit),
        totalMessages: totalCount,
        hasMore: page * limit < totalCount
      }
    });

  } catch (error) {
    console.error('Ошибка получения сообщений группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 84. Отправка сообщения в группу
app.post('/api/groups/:groupId/messages', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const { text, type_id = 1, forwarded_message_id } = req.body;
  const userId = req.user.userId;

  if (!text || text.trim() === '') {
    return res.status(400).json({ 
      success: false, 
      error: 'Текст сообщения обязателен' 
    });
  }

  try {
    const memberCheck = await pool.query(
      'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы не можете отправлять сообщения в эту группу' 
      });
    }

    const encryptedText = encryptMessage(text.trim());

    const insertQuery = `
      INSERT INTO group_messages 
        (group_id, user_id, text, type_id, forwarded_message_id, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING id, created_at
    `;

    const result = await pool.query(insertQuery, [
      groupId,
      userId,
      encryptedText,
      type_id,
      forwarded_message_id || null
    ]);

    const userResult = await pool.query(
      'SELECT nickname, name, avatar_url FROM users WHERE id = $1',
      [userId]
    );

    const user = userResult.rows[0];
    const decryptedName = user.name ? decryptString(user.name) : null;
    const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
    let senderName = decryptedNickname || decryptedName || `User ${userId}`;

    const groupResult = await pool.query(
      'SELECT name FROM groups WHERE id = $1',
      [groupId]
    );

    const groupName = groupResult.rows[0]?.name || 'Группа';

    const notification = {
      type: 'new_message',
      group_id: parseInt(groupId),
      group_title: groupName,
      sender_id: userId,
      sender_name: senderName,
      sender_avatar: user.avatar_url,
      message: {
        id: result.rows[0].id,
        user_id: userId,
        text: text.trim(),
        type_id: type_id,
        created_at: result.rows[0].created_at
      }
    };

    const participants = await pool.query(
      'SELECT user_id FROM group_members WHERE group_id = $1 AND user_id != $2',
      [groupId, userId]
    );

    for (const row of participants.rows) {
      if (typeof sendToUser === 'function') {
        sendToUser(row.user_id, notification);
      }
    }

    res.json({
      success: true,
      id: result.rows[0].id,
      created_at: result.rows[0].created_at
    });

  } catch (error) {
    console.error('Ошибка отправки сообщения в группу:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 85. Удаление сообщения из группы
app.delete('/api/groups/:groupId/messages/:messageId', authMiddleware, async (req, res) => {
  const { groupId, messageId } = req.params;
  const userId = req.user.userId;

  try {
    const messageCheck = await pool.query(
      'SELECT user_id FROM group_messages WHERE id = $1 AND group_id = $2',
      [messageId, groupId]
    );

    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Сообщение не найдено' 
      });
    }

    if (messageCheck.rows[0].user_id !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Вы можете удалять только свои сообщения' 
      });
    }

    await pool.query(
      'DELETE FROM group_messages WHERE id = $1 AND group_id = $2',
      [messageId, groupId]
    );

    res.json({ 
      success: true, 
      message: 'Сообщение удалено' 
    });

  } catch (error) {
    console.error('Ошибка удаления сообщения из группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 86. Выход из группы
app.delete('/api/groups/:groupId/members/:userId', authMiddleware, async (req, res) => {
  const { groupId, userId } = req.params;
  const currentUserId = req.user.userId;

  if (parseInt(userId) !== currentUserId) {
    return res.status(403).json({ 
      success: false, 
      error: 'Вы можете удалить только себя из группы' 
    });
  }

  try {
    const adminCheck = await pool.query(`
      SELECT COUNT(*) as admin_count 
      FROM group_members 
      WHERE group_id = $1 AND role = 'admin'
    `, [groupId]);

    const userRole = await pool.query(
      'SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, currentUserId]
    );

    if (userRole.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Вы не являетесь участником этой группы' 
      });
    }

    if (userRole.rows[0].role === 'admin' && parseInt(adminCheck.rows[0].admin_count) === 1) {
      return res.status(400).json({ 
        success: false, 
        error: 'Вы последний администратор. Назначьте другого администратора перед выходом.' 
      });
    }

    await pool.query(
      'DELETE FROM group_members WHERE group_id = $1 AND user_id = $2',
      [groupId, currentUserId]
    );

    res.json({ 
      success: true, 
      message: 'Вы вышли из группы' 
    });

  } catch (error) {
    console.error('Ошибка выхода из группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 87. Получение настроек уведомлений группы
app.get('/api/groups/:groupId/notification-settings', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    const result = await pool.query(
      `SELECT notifications_enabled, mute_duration, muted_until
       FROM group_notification_settings
       WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );

    if (result.rows.length === 0) {
      await pool.query(
        `INSERT INTO group_notification_settings (group_id, user_id, notifications_enabled, created_at, updated_at)
         VALUES ($1, $2, TRUE, NOW(), NOW())`,
        [groupId, userId]
      );

      return res.json({
        notifications_enabled: true,
        mute_duration: null,
        muted_until: null
      });
    }

    const settings = result.rows[0];

    if (settings.muted_until && new Date(settings.muted_until) < new Date()) {
      await pool.query(
        `UPDATE group_notification_settings
         SET notifications_enabled = TRUE, mute_duration = NULL, muted_until = NULL, updated_at = NOW()
         WHERE group_id = $1 AND user_id = $2`,
        [groupId, userId]
      );

      return res.json({
        notifications_enabled: true,
        mute_duration: null,
        muted_until: null
      });
    }

    res.json(settings);

  } catch (error) {
    console.error('Ошибка получения настроек уведомлений группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 88. Обновление настроек уведомлений группы
app.put('/api/groups/:groupId/notification-settings', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;
  const { notifications_enabled, mute_duration, muted_until } = req.body;

  try {
    await pool.query(
      `INSERT INTO group_notification_settings 
         (group_id, user_id, notifications_enabled, mute_duration, muted_until, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (group_id, user_id) 
       DO UPDATE SET
         notifications_enabled = EXCLUDED.notifications_enabled,
         mute_duration = EXCLUDED.mute_duration,
         muted_until = EXCLUDED.muted_until,
         updated_at = NOW()`,
      [groupId, userId, notifications_enabled, mute_duration, muted_until]
    );

    res.json({ success: true });

  } catch (error) {
    console.error('Ошибка обновления настроек уведомлений группы:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 89. Пометить группу как прочитанную
app.post('/api/groups/:groupId/mark-read', authMiddleware, async (req, res) => {
  const { groupId } = req.params;
  const userId = req.user.userId;

  try {
    const last = await pool.query(
      `SELECT id FROM group_messages
       WHERE group_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [groupId]
    );

    if (last.rows.length > 0) {
      await pool.query(
        `UPDATE group_members
         SET last_read_message_id = $1
         WHERE group_id = $2 AND user_id = $3`,
        [last.rows[0].id, groupId, userId]
      );
    }

    res.json({ success: true });

  } catch (error) {
    console.error('Ошибка пометки группы как прочитанной:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Ошибка сервера' 
    });
  }
});

// 90. Загрузка файлов в группу
app.post('/api/groups/upload', authMiddleware, uploadChat.any(), async (req, res) => {
  try {
    console.log('📤 Upload to group request received:', {
      files: req.files?.map(f => ({
        fieldname: f.fieldname,
        originalname: f.originalname,
        mimetype: f.mimetype,
        size: f.size
      })),
      body: req.body
    });

    const files = [];
    if (req.file) files.push(req.file);
    if (req.files && Array.isArray(req.files)) files.push(...req.files);

    if (files.length === 0) {
      return res.status(400).json({ 
        success: false,
        error: 'Файлы не получены сервером' 
      });
    }

    const results = [];
    const errors = [];

    for (const file of files) {
      try {
        const { originalname, mimetype, size, buffer } = file;
        const userId = req.user.userId;
        const { group_id, text } = req.body;

        if (!group_id) {
          errors.push({
            file: originalname,
            error: 'group_id обязателен'
          });
          continue;
        }

        const memberCheck = await pool.query(
          'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
          [group_id, userId]
        );

        if (memberCheck.rows.length === 0) {
          errors.push({
            file: originalname,
            error: 'Вы не являетесь участником этой группы'
          });
          continue;
        }

        const typeId = getFileTypeId(mimetype, originalname);
        
        const typeResult = await pool.query(
          'SELECT name FROM message_types WHERE id = $1',
          [typeId]
        );
        const typeName = typeResult.rows[0]?.name || 'file';

        console.log(`📄 Файл для группы ${group_id}: ${originalname}, тип: ${typeName} (ID: ${typeId})`);
        
        let s3Url;
        try {
          s3Url = await uploadToS3(buffer, originalname, mimetype);
          console.log(`✅ Файл загружен в S3: ${s3Url}`);
        } catch (s3Error) {
          console.error('❌ S3 upload failed:', s3Error);
          errors.push({
            file: originalname,
            error: 'Ошибка загрузки в S3',
            details: s3Error.message
          });
          continue;
        }
        
        const fileHash = crypto.randomBytes(16).toString('hex');

        let messageText = '';
        if (text && text.trim()) {
          messageText = encryptMessage(text.trim());
        } else {
          messageText = `Файл: ${originalname}`;
        }

        const insertResult = await pool.query(`
          INSERT INTO group_messages 
            (group_id, user_id, text, type_id, file_url, file_hash, file_size, created_at) 
          VALUES ($1, $2, $3, $4, $5, $6, $7, NOW()) 
          RETURNING id, created_at
        `, [group_id, userId, messageText, typeId, s3Url, fileHash, size]);

        const userResult = await pool.query(
          'SELECT nickname, name, avatar_url FROM users WHERE id = $1',
          [userId]
        );

        const user = userResult.rows[0];
        const decryptedName = user.name ? decryptString(user.name) : null;
        const decryptedNickname = user.nickname ? decryptString(user.nickname) : null;
        let senderName = decryptedNickname || decryptedName || `User ${userId}`;

        const groupResult = await pool.query(
          'SELECT name FROM groups WHERE id = $1',
          [group_id]
        );

        const groupName = groupResult.rows[0]?.name || 'Группа';

        const notification = {
          type: 'new_message',
          group_id: parseInt(group_id),
          group_title: groupName,
          sender_id: userId,
          sender_name: senderName,
          sender_avatar: user.avatar_url,
          message: {
            id: insertResult.rows[0].id,
            user_id: userId,
            text: text?.trim() || '',
            file_url: s3Url,
            type_id: typeId,
            created_at: insertResult.rows[0].created_at
          }
        };

        const participants = await pool.query(
          'SELECT user_id FROM group_members WHERE group_id = $1 AND user_id != $2',
          [group_id, userId]
        );

        for (const row of participants.rows) {
          if (typeof sendToUser === 'function') {
            sendToUser(row.user_id, notification);
          }
        }

        results.push({
          success: true,
          file_url: s3Url,
          file_name: fileHash,
          original_name: originalname,
          file_type: typeName,
          file_size: size,
          message_id: insertResult.rows[0].id,
          created_at: insertResult.rows[0].created_at,
          type_id: typeId
        });

        console.log(`✅ Файл для группы ${group_id} обработан: ${originalname}`);

      } catch (fileError) {
        console.error(`❌ Ошибка обработки файла:`, fileError);
        errors.push({
          file: file.originalname,
          error: fileError.message
        });
      }
    }

    if (results.length === 0) {
      return res.status(500).json({
        success: false,
        error: 'Не удалось обработать ни один файл',
        errors: errors
      });
    }

    res.json({
      success: true,
      results: results,
      errors: errors.length > 0 ? errors : undefined
    });

  } catch (error) {
    console.error('❌ Group upload error:', error);
    res.status(500).json({
      success: false,
      error: 'Внутренняя ошибка сервера',
      details: error.message
    });
  }
});

// 91. GET Получение списка групп пользователя
app.get('/api/groups', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;
    
    console.log(`👥 Запрос списка групп для пользователя ${userId}`);
    
    const result = await pool.query(`
      SELECT 
        g.id,
        g.name,
        g.description,
        g.avatar_url,
        g.avatar_color,
        g.created_by,
        g.created_at,
        gm.role,
        COUNT(DISTINCT gm2.user_id) as members_count,
        (
          SELECT COUNT(*) 
          FROM group_messages gm3 
          WHERE gm3.group_id = g.id
        ) as messages_count,
        (
          SELECT created_at 
          FROM group_messages gm4 
          WHERE gm4.group_id = g.id 
          ORDER BY created_at DESC 
          LIMIT 1
        ) as last_message_time
      FROM groups g
      INNER JOIN group_members gm ON g.id = gm.group_id AND gm.user_id = $1
      LEFT JOIN group_members gm2 ON g.id = gm2.group_id
      GROUP BY g.id, g.name, g.description, g.avatar_url, g.avatar_color, 
               g.created_by, g.created_at, gm.role
      ORDER BY last_message_time DESC NULLS LAST, g.created_at DESC
    `, [userId]);
    
    console.log(`✅ Найдено ${result.rows.length} групп для пользователя ${userId}`);
    
    res.json({
      success: true,
      groups: result.rows,
      count: result.rows.length
    });
    
  } catch (error) {
    console.error('❌ Ошибка получения списка групп:', error);
    res.status(500).json({ 
      success: false,
      error: 'Ошибка сервера',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// ==================== ЗАПУСК СЕРВЕРА ====================
const server = http.createServer(app);

// Настройка WebSocket
const wss = new WebSocketServer({ 
  server,
  path: '/ws'
});

// Хранилище активных WebSocket соединений
const clients = new Map();

wss.on('connection', (ws, req) => {
  console.log('🔌 Новое WebSocket соединение');
  
  const urlParams = new URLSearchParams(req.url.split('?')[1]);
  const token = urlParams.get('token');
  
  if (!token) {
    console.log('❌ WebSocket: нет токена');
    ws.close(1008, 'Token required');
    return;
  }
  
  let userId;
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    userId = decoded.userId;
    console.log(`✅ WebSocket: пользователь ${userId} подключился`);
    
    clients.set(userId, ws);
    
    ws.send(JSON.stringify({ 
      type: 'connection_established', 
      userId: userId,
      message: 'WebSocket connected successfully' 
    }));
    
  } catch (error) {
    console.log('❌ WebSocket: неверный токен', error.message);
    ws.close(1008, 'Invalid token');
    return;
  }
  
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      
      switch (message.type) {
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
          
        case 'typing':
          if (message.chat_id && message.is_typing !== undefined) {
            broadcastToChatParticipants(message.chat_id, userId, {
              type: 'typing',
              user_id: userId,
              chat_id: message.chat_id,
              is_typing: message.is_typing
            });
          }
          break;
          
        case 'read':
          if (message.chat_id && message.message_id) {
            broadcastToChatParticipants(message.chat_id, userId, {
              type: 'read_receipt',
              user_id: userId,
              chat_id: message.chat_id,
              message_id: message.message_id
            });
          }
          break;
          
        case 'voip_token':
          console.log(`📱 VoIP токен для пользователя ${userId}:`, message.token);
          break;
          
        default:
          console.log('⚠️ Неизвестный тип сообщения:', message.type);
      }
      
    } catch (error) {
      console.error('❌ Ошибка обработки WebSocket сообщения:', error);
    }
  });
  
  ws.on('close', (code, reason) => {
    console.log(`🔌 WebSocket отключен: пользователь ${userId}, код: ${code}`);
    clients.delete(userId);
  });
  
  ws.on('error', (error) => {
    console.error(`❌ WebSocket ошибка для пользователя ${userId}:`, error.message);
  });
});

// Функция для отправки сообщения конкретному пользователю
function sendToUser(userId, message) {
  const client = clients.get(userId);
  if (client && client.readyState === 1) {
    client.send(JSON.stringify(message));
    return true;
  }
  return false;
}

// Функция для отправки уведомлений всем участникам чата
async function broadcastToChatParticipants(chatId, senderId, message) {
  try {
    const result = await pool.query(
      'SELECT user_id FROM chat_participants WHERE chat_id = $1 AND user_id != $2',
      [chatId, senderId]
    );
    
    for (const row of result.rows) {
      sendToUser(row.user_id, message);
    }
  } catch (error) {
    console.error('❌ Ошибка отправки уведомлений участникам чата:', error);
  }
}

// Запускаем сервер
server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n✅ HTTP сервер запущен: http://localhost:${PORT}`);
    console.log(`✅ WebSocket сервер запущен: ws://localhost:${PORT}/ws`);
});

// Обработка ошибок порта
server.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
        console.log(`❌ Порт ${PORT} занят. Пробуем порт ${parseInt(PORT) + 1}...`);
        const altPort = parseInt(PORT) + 1;
        server.listen(altPort, '0.0.0.0', () => {
            console.log(`✅ Сервер запущен на порту ${altPort}`);
        });
    } else {
        console.error('❌ Ошибка сервера:', error);
        process.exit(1);
    }
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Получен SIGINT. Graceful shutdown...');
    console.log(`🗑️  Очистка ${verificationCodes.size} кодов подтверждения...`);
    verificationCodes.clear();
    console.log(`🗑️  Очистка ${resetPasswordCodes.size} кодов сброса пароля...`);
    resetPasswordCodes.clear();
    server.close(() => {
        console.log('✅ Сервер остановлен');
        pool.end(() => {
            console.log('✅ Подключение к БД закрыто');
            process.exit(0);
        });
    });
});

process.on('SIGTERM', () => {
    console.log('\n🛑 Получен SIGTERM. Graceful shutdown...');
    console.log(`🗑️  Очистка ${verificationCodes.size} кодов подтверждения...`);
    verificationCodes.clear();
    console.log(`🗑️  Очистка ${resetPasswordCodes.size} кодов сброса пароля...`);
    resetPasswordCodes.clear();
    server.close(() => {
        console.log('✅ Сервер остановлен');
        pool.end(() => {
            console.log('✅ Подключение к БД закрыто');
            process.exit(0);
        });
    });
});