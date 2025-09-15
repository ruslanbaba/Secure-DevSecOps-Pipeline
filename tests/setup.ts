import { jest } from '@jest/globals';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: '.env.test' });

// Global test setup
beforeAll(() => {
  // Set test environment
  process.env.NODE_ENV = 'test';
  
  // Suppress console.log in tests unless debugging
  if (!process.env.DEBUG_TESTS) {
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'info').mockImplementation(() => {});
  }
  
  // Set default timeouts
  jest.setTimeout(30000);
});

afterAll(() => {
  // Cleanup after all tests
  jest.restoreAllMocks();
});

// Global error handler for unhandled rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit the process in tests
});

// Custom matchers
expect.extend({
  toBeWithinRange(received: number, floor: number, ceiling: number) {
    const pass = received >= floor && received <= ceiling;
    if (pass) {
      return {
        message: () =>
          `expected ${received} not to be within range ${floor} - ${ceiling}`,
        pass: true,
      };
    } else {
      return {
        message: () =>
          `expected ${received} to be within range ${floor} - ${ceiling}`,
        pass: false,
      };
    }
  },
  
  toHaveValidResponseTime(received: number, maxTime: number = 1000) {
    const pass = received <= maxTime;
    if (pass) {
      return {
        message: () =>
          `expected response time ${received}ms not to be under ${maxTime}ms`,
        pass: true,
      };
    } else {
      return {
        message: () =>
          `expected response time ${received}ms to be under ${maxTime}ms`,
        pass: false,
      };
    }
  },
  
  toBeSecureHeader(received: string | null) {
    if (!received) {
      return {
        message: () => 'expected security header to be present',
        pass: false,
      };
    }
    
    // Basic security header validation
    const isSecure = received.length > 0 && 
                    !received.includes('unsafe-inline') && 
                    !received.includes('unsafe-eval');
    
    if (isSecure) {
      return {
        message: () => `expected ${received} not to be a secure header`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be a secure header`,
        pass: false,
      };
    }
  }
});

// Extend Jest matchers type definitions
declare global {
  namespace jest {
    interface Matchers<R> {
      toBeWithinRange(floor: number, ceiling: number): R;
      toHaveValidResponseTime(maxTime?: number): R;
      toBeSecureHeader(): R;
    }
  }
}

// Test utilities
export const testUtils = {
  // Create test user
  createTestUser: () => ({
    username: `testuser_${Date.now()}`,
    password: 'TestPass123!',
    email: `test_${Date.now()}@example.com`
  }),
  
  // Generate test data
  generateTestData: (count: number = 1) => {
    return Array.from({ length: count }, (_, i) => ({
      id: i + 1,
      name: `Test Item ${i + 1}`,
      description: `Description for test item ${i + 1}`,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    }));
  },
  
  // Wait helper
  wait: (ms: number) => new Promise(resolve => setTimeout(resolve, ms)),
  
  // Retry helper
  retry: async <T>(
    fn: () => Promise<T>, 
    maxAttempts: number = 3, 
    delay: number = 1000
  ): Promise<T> => {
    let lastError;
    
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        if (attempt < maxAttempts) {
          await testUtils.wait(delay);
        }
      }
    }
    
    throw lastError;
  },
  
  // Clean test data
  cleanupTestData: async () => {
    // Implementation would depend on your data storage
    // This is a placeholder for cleanup operations
    if (process.env.NODE_ENV === 'test') {
      // Perform test data cleanup
      console.log('Cleaning up test data...');
    }
  }
};

// Export for use in tests
export { jest };