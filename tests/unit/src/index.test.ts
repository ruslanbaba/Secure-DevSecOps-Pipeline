import { describe, test, expect, beforeEach, afterEach } from '@jest/globals';
import request from 'supertest';
import { app } from '../../../src/index';

describe('Application Unit Tests', () => {
  beforeEach(() => {
    // Setup test environment
    process.env.NODE_ENV = 'test';
  });

  afterEach(() => {
    // Cleanup after each test
    jest.clearAllMocks();
  });

  describe('Health Check Endpoint', () => {
    test('should return 200 OK for health check', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toEqual({
        status: 'healthy',
        timestamp: expect.any(String),
        uptime: expect.any(Number),
        version: expect.any(String)
      });
    });

    test('should include required headers in health check', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.headers['content-type']).toMatch(/json/);
      expect(response.headers['cache-control']).toBe('no-cache');
    });
  });

  describe('Security Headers', () => {
    test('should include security headers in all responses', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.headers['x-content-type-options']).toBe('nosniff');
      expect(response.headers['x-frame-options']).toBe('DENY');
      expect(response.headers['x-xss-protection']).toBe('1; mode=block');
      expect(response.headers['strict-transport-security']).toBeDefined();
    });
  });

  describe('Error Handling', () => {
    test('should handle 404 errors gracefully', async () => {
      const response = await request(app)
        .get('/nonexistent')
        .expect(404);

      expect(response.body).toEqual({
        error: 'Not Found',
        message: 'The requested resource was not found',
        timestamp: expect.any(String)
      });
    });

    test('should not expose sensitive information in errors', async () => {
      const response = await request(app)
        .get('/nonexistent')
        .expect(404);

      expect(response.body.stack).toBeUndefined();
      expect(response.body.message).not.toContain('internal');
      expect(response.body.message).not.toContain('database');
    });
  });

  describe('Input Validation', () => {
    test('should validate request parameters', async () => {
      const response = await request(app)
        .post('/api/data')
        .send({ invalid: 'data' })
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
    });

    test('should sanitize user input', async () => {
      const maliciousInput = '<script>alert("xss")</script>';
      const response = await request(app)
        .post('/api/data')
        .send({ name: maliciousInput })
        .expect(400);

      expect(response.body.message).not.toContain('<script>');
    });
  });

  describe('Rate Limiting', () => {
    test('should enforce rate limits', async () => {
      // Make multiple requests quickly
      const promises = Array.from({ length: 101 }, () =>
        request(app).get('/health')
      );

      const responses = await Promise.allSettled(promises);
      const rejectedCount = responses.filter(
        result => result.status === 'fulfilled' && 
        (result.value as any).status === 429
      ).length;

      expect(rejectedCount).toBeGreaterThan(0);
    }, 10000);
  });

  describe('Authentication', () => {
    test('should reject requests without valid tokens', async () => {
      const response = await request(app)
        .get('/api/protected')
        .expect(401);

      expect(response.body.error).toBe('Unauthorized');
    });

    test('should accept requests with valid tokens', async () => {
      const validToken = 'valid-test-token';
      const response = await request(app)
        .get('/api/protected')
        .set('Authorization', `Bearer ${validToken}`)
        .expect(200);

      expect(response.body.message).toBe('Access granted');
    });
  });

  describe('Logging', () => {
    test('should log requests without sensitive data', async () => {
      const mockLog = jest.spyOn(console, 'log').mockImplementation();
      
      await request(app)
        .post('/api/data')
        .send({ password: 'secret123', data: 'normal' });

      const logCalls = mockLog.mock.calls.flat();
      const logString = logCalls.join(' ');
      
      expect(logString).not.toContain('secret123');
      expect(logString).toContain('data');
      
      mockLog.mockRestore();
    });
  });
});