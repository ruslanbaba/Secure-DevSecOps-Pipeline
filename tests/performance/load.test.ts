import { describe, test, expect, beforeAll, afterAll } from '@jest/globals';
import autocannon from 'autocannon';
import { promisify } from 'util';

const sleep = promisify(setTimeout);

describe('Performance Tests', () => {
  const APP_URL = process.env.PERF_APP_URL || 'http://localhost:3000';
  
  beforeAll(async () => {
    // Warm up the application
    await fetch(`${APP_URL}/health`).catch(() => {});
    await sleep(2000);
  });

  describe('Load Testing', () => {
    test('should handle basic load on health endpoint', async () => {
      const result = await autocannon({
        url: `${APP_URL}/health`,
        connections: 10,
        duration: 10,
        pipelining: 1
      });

      expect(result.non2xx).toBe(0); // No errors
      expect(result.requests.average).toBeGreaterThan(100); // At least 100 req/sec
      expect(result.latency.p99).toBeLessThan(1000); // 99th percentile under 1s
    }, 30000);

    test('should handle moderate load with authentication', async () => {
      // First get auth token
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });

      const { token } = await authResponse.json();

      const result = await autocannon({
        url: `${APP_URL}/api/protected`,
        connections: 5,
        duration: 10,
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      expect(result.non2xx).toBe(0);
      expect(result.requests.average).toBeGreaterThan(50);
      expect(result.latency.p95).toBeLessThan(2000); // 95th percentile under 2s
    }, 30000);

    test('should handle data creation load', async () => {
      // Get auth token
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });

      const { token } = await authResponse.json();

      const result = await autocannon({
        url: `${APP_URL}/api/data`,
        method: 'POST',
        connections: 3,
        duration: 10,
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name: 'Load Test Item',
          description: 'Created during load testing'
        })
      });

      expect(result.non2xx + result.timeouts).toBeLessThan(result.requests.total * 0.01); // Less than 1% errors
      expect(result.latency.p90).toBeLessThan(3000); // 90th percentile under 3s
    }, 30000);
  });

  describe('Stress Testing', () => {
    test('should gracefully degrade under high load', async () => {
      const result = await autocannon({
        url: `${APP_URL}/health`,
        connections: 50,
        duration: 15,
        pipelining: 1
      });

      // Under stress, we expect some degradation but not complete failure
      const errorRate = (result.non2xx + result.timeouts) / result.requests.total;
      expect(errorRate).toBeLessThan(0.05); // Less than 5% error rate
      
      // Response time might be higher under stress but should still be reasonable
      expect(result.latency.p99).toBeLessThan(5000); // 99th percentile under 5s
    }, 45000);

    test('should recover after stress period', async () => {
      // Apply stress
      await autocannon({
        url: `${APP_URL}/health`,
        connections: 100,
        duration: 5
      });

      // Wait for recovery
      await sleep(5000);

      // Test normal performance
      const result = await autocannon({
        url: `${APP_URL}/health`,
        connections: 5,
        duration: 5
      });

      expect(result.non2xx).toBe(0);
      expect(result.latency.p95).toBeLessThan(1000); // Should be back to normal
    }, 30000);
  });

  describe('Endurance Testing', () => {
    test('should maintain performance over extended period', async () => {
      const duration = 60; // 1 minute test
      const result = await autocannon({
        url: `${APP_URL}/health`,
        connections: 10,
        duration: duration,
        pipelining: 1
      });

      expect(result.non2xx).toBe(0);
      expect(result.requests.average).toBeGreaterThan(50);
      
      // Check for memory leaks or performance degradation
      const avgLatency = result.latency.average;
      expect(avgLatency).toBeLessThan(500); // Average latency under 500ms
    }, 120000);
  });

  describe('Concurrent User Simulation', () => {
    test('should handle multiple user scenarios simultaneously', async () => {
      const scenarios = [
        // Scenario 1: Health checks
        autocannon({
          url: `${APP_URL}/health`,
          connections: 5,
          duration: 20
        }),
        
        // Scenario 2: Authentication
        autocannon({
          url: `${APP_URL}/auth/login`,
          method: 'POST',
          connections: 3,
          duration: 20,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            username: 'testuser',
            password: 'testpass123'
          })
        })
      ];

      const results = await Promise.all(scenarios);

      // All scenarios should complete successfully
      results.forEach((result, index) => {
        expect(result.non2xx).toBeLessThan(result.requests.total * 0.02); // Less than 2% errors
        expect(result.latency.p95).toBeLessThan(2000); // 95th percentile under 2s
      });
    }, 60000);
  });

  describe('Resource Usage', () => {
    test('should not exhibit memory leaks under load', async () => {
      // Get initial memory usage
      const initialMemory = await getMemoryUsage();
      
      // Apply sustained load
      await autocannon({
        url: `${APP_URL}/health`,
        connections: 20,
        duration: 30
      });

      // Wait for potential garbage collection
      await sleep(5000);

      // Get final memory usage
      const finalMemory = await getMemoryUsage();

      // Memory should not have increased significantly (allowing for some overhead)
      const memoryIncrease = finalMemory - initialMemory;
      expect(memoryIncrease).toBeLessThan(initialMemory * 0.5); // Less than 50% increase
    }, 60000);

    test('should handle file upload performance', async () => {
      // Create a test file buffer (1MB)
      const testFile = Buffer.alloc(1024 * 1024, 'test data');
      
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });

      const { token } = await authResponse.json();

      const start = Date.now();
      const uploadResponse = await fetch(`${APP_URL}/api/upload`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/octet-stream'
        },
        body: testFile
      });

      const uploadTime = Date.now() - start;

      expect(uploadResponse.status).toBe(200);
      expect(uploadTime).toBeLessThan(10000); // Upload should complete within 10s
    }, 30000);
  });

  describe('Database Performance', () => {
    test('should handle concurrent database operations', async () => {
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });

      const { token } = await authResponse.json();

      // Test concurrent reads
      const readResult = await autocannon({
        url: `${APP_URL}/api/data`,
        connections: 10,
        duration: 15,
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      expect(readResult.non2xx).toBe(0);
      expect(readResult.latency.p95).toBeLessThan(1500); // Database reads under 1.5s

      // Test concurrent writes
      const writeResult = await autocannon({
        url: `${APP_URL}/api/data`,
        method: 'POST',
        connections: 5,
        duration: 10,
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name: 'Concurrent Write Test',
          description: 'Testing concurrent database writes'
        })
      });

      const writeErrorRate = writeResult.non2xx / writeResult.requests.total;
      expect(writeErrorRate).toBeLessThan(0.05); // Less than 5% write errors
    }, 45000);
  });
});

async function getMemoryUsage(): Promise<number> {
  try {
    const response = await fetch(`${process.env.PERF_APP_URL || 'http://localhost:3000'}/api/stats/memory`);
    const data = await response.json();
    return data.heapUsed || 0;
  } catch {
    return 0; // If endpoint doesn't exist, return 0
  }
}