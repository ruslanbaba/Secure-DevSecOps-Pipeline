import { describe, test, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { spawn, ChildProcess } from 'child_process';
import { promisify } from 'util';

const sleep = promisify(setTimeout);

describe('Integration Tests', () => {
  let appProcess: ChildProcess;
  const APP_URL = 'http://localhost:3000';

  beforeAll(async () => {
    // Start the application
    appProcess = spawn('npm', ['start'], {
      env: { ...process.env, NODE_ENV: 'test', PORT: '3000' },
      stdio: 'inherit'
    });

    // Wait for the app to start
    await sleep(5000);
  }, 30000);

  afterAll(async () => {
    if (appProcess) {
      appProcess.kill();
    }
  });

  describe('End-to-End API Flow', () => {
    test('should handle complete user journey', async () => {
      // Health check
      const healthResponse = await request(APP_URL)
        .get('/health')
        .expect(200);

      expect(healthResponse.body.status).toBe('healthy');

      // Authentication flow
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        })
        .expect(200);

      expect(authResponse.body.token).toBeDefined();
      const token = authResponse.body.token;

      // Protected resource access
      const protectedResponse = await request(APP_URL)
        .get('/api/protected')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);

      expect(protectedResponse.body.message).toBe('Access granted');

      // Data operations
      const createResponse = await request(APP_URL)
        .post('/api/data')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Test Item',
          description: 'Integration test data'
        })
        .expect(201);

      expect(createResponse.body.id).toBeDefined();
      const itemId = createResponse.body.id;

      // Retrieve data
      const getResponse = await request(APP_URL)
        .get(`/api/data/${itemId}`)
        .set('Authorization', `Bearer ${token}`)
        .expect(200);

      expect(getResponse.body.name).toBe('Test Item');

      // Update data
      const updateResponse = await request(APP_URL)
        .put(`/api/data/${itemId}`)
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Updated Test Item',
          description: 'Updated description'
        })
        .expect(200);

      expect(updateResponse.body.name).toBe('Updated Test Item');

      // Delete data
      await request(APP_URL)
        .delete(`/api/data/${itemId}`)
        .set('Authorization', `Bearer ${token}`)
        .expect(204);

      // Verify deletion
      await request(APP_URL)
        .get(`/api/data/${itemId}`)
        .set('Authorization', `Bearer ${token}`)
        .expect(404);
    }, 30000);
  });

  describe('Database Integration', () => {
    test('should persist data correctly', async () => {
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        });

      const token = authResponse.body.token;

      // Create multiple items
      const items = await Promise.all([
        request(APP_URL)
          .post('/api/data')
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Item 1', description: 'First item' }),
        request(APP_URL)
          .post('/api/data')
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Item 2', description: 'Second item' }),
        request(APP_URL)
          .post('/api/data')
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Item 3', description: 'Third item' })
      ]);

      expect(items.every(item => item.status === 201)).toBe(true);

      // List all items
      const listResponse = await request(APP_URL)
        .get('/api/data')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);

      expect(listResponse.body.length).toBeGreaterThanOrEqual(3);
      expect(listResponse.body.some((item: any) => item.name === 'Item 1')).toBe(true);
    });

    test('should handle concurrent operations', async () => {
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        });

      const token = authResponse.body.token;

      // Create item first
      const createResponse = await request(APP_URL)
        .post('/api/data')
        .set('Authorization', `Bearer ${token}`)
        .send({ name: 'Concurrent Item', description: 'Test concurrency' });

      const itemId = createResponse.body.id;

      // Perform concurrent updates
      const updates = await Promise.allSettled([
        request(APP_URL)
          .put(`/api/data/${itemId}`)
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Update 1', description: 'First update' }),
        request(APP_URL)
          .put(`/api/data/${itemId}`)
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Update 2', description: 'Second update' }),
        request(APP_URL)
          .put(`/api/data/${itemId}`)
          .set('Authorization', `Bearer ${token}`)
          .send({ name: 'Update 3', description: 'Third update' })
      ]);

      // At least one update should succeed
      const successfulUpdates = updates.filter(
        result => result.status === 'fulfilled' && 
        (result.value as any).status === 200
      );

      expect(successfulUpdates.length).toBeGreaterThan(0);
    });
  });

  describe('Error Recovery', () => {
    test('should recover from temporary failures', async () => {
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        });

      const token = authResponse.body.token;

      // Simulate network failure scenario
      let attempts = 0;
      let success = false;
      const maxAttempts = 3;

      while (attempts < maxAttempts && !success) {
        try {
          const response = await request(APP_URL)
            .get('/api/data')
            .set('Authorization', `Bearer ${token}`)
            .timeout(5000);

          if (response.status === 200) {
            success = true;
          }
        } catch (error) {
          attempts++;
          if (attempts < maxAttempts) {
            await sleep(1000); // Wait before retry
          }
        }
      }

      expect(success).toBe(true);
    });
  });

  describe('Security Integration', () => {
    test('should prevent SQL injection', async () => {
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        });

      const token = authResponse.body.token;

      // Attempt SQL injection
      const maliciousInput = "'; DROP TABLE users; --";
      const response = await request(APP_URL)
        .post('/api/data')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: maliciousInput,
          description: 'Normal description'
        });

      // Should either reject the input or sanitize it
      expect([400, 422, 201]).toContain(response.status);

      if (response.status === 201) {
        // If accepted, ensure it's sanitized
        expect(response.body.name).not.toContain('DROP TABLE');
      }
    });

    test('should prevent XSS attacks', async () => {
      const authResponse = await request(APP_URL)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'testpass123'
        });

      const token = authResponse.body.token;

      const xssPayload = '<script>alert("xss")</script>';
      const response = await request(APP_URL)
        .post('/api/data')
        .set('Authorization', `Bearer ${token}`)
        .send({
          name: 'Normal Name',
          description: xssPayload
        });

      if (response.status === 201) {
        expect(response.body.description).not.toContain('<script>');
      }
    });
  });
});