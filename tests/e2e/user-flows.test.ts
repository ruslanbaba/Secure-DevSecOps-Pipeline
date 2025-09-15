import { describe, test, expect, beforeAll, afterAll, beforeEach } from '@jest/globals';
import puppeteer, { Browser, Page } from 'puppeteer';

describe('End-to-End Tests', () => {
  let browser: Browser;
  let page: Page;
  const APP_URL = process.env.E2E_APP_URL || 'http://localhost:3000';

  beforeAll(async () => {
    browser = await puppeteer.launch({
      headless: process.env.CI === 'true',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu'
      ]
    });
  }, 30000);

  beforeEach(async () => {
    page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 720 });
    
    // Set up request/response monitoring
    await page.setRequestInterception(true);
    page.on('request', (req) => {
      req.continue();
    });
  });

  afterAll(async () => {
    if (browser) {
      await browser.close();
    }
  });

  describe('Application Accessibility', () => {
    test('should meet WCAG accessibility standards', async () => {
      await page.goto(APP_URL);
      
      // Check for essential accessibility elements
      const hasMainLandmark = await page.$('main') !== null;
      const hasSkipLink = await page.$('a[href="#main-content"]') !== null;
      const hasTitle = await page.$eval('title', el => el.textContent?.length > 0);
      
      expect(hasMainLandmark || hasSkipLink).toBe(true);
      expect(hasTitle).toBe(true);

      // Check color contrast (basic check)
      const bodyStyles = await page.evaluate(() => {
        const body = document.body;
        const computedStyle = window.getComputedStyle(body);
        return {
          color: computedStyle.color,
          backgroundColor: computedStyle.backgroundColor
        };
      });

      expect(bodyStyles.color).toBeDefined();
      expect(bodyStyles.backgroundColor).toBeDefined();
    });

    test('should be keyboard navigable', async () => {
      await page.goto(APP_URL);
      
      // Test tab navigation
      await page.keyboard.press('Tab');
      const activeElement = await page.evaluate(() => document.activeElement?.tagName);
      
      // Should focus on a focusable element
      expect(['A', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA'].includes(activeElement || '')).toBe(true);
    });
  });

  describe('User Authentication Flow', () => {
    test('should handle complete login flow', async () => {
      await page.goto(`${APP_URL}/login`);
      
      // Fill login form
      await page.waitForSelector('input[name="username"]', { timeout: 5000 });
      await page.type('input[name="username"]', 'testuser');
      await page.type('input[name="password"]', 'testpass123');
      
      // Submit form
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle0' }),
        page.click('button[type="submit"]')
      ]);
      
      // Verify successful login
      const url = page.url();
      expect(url).toContain('/dashboard');
      
      // Check for user indicator
      const userIndicator = await page.$('.user-info, [data-testid="user-name"]');
      expect(userIndicator).toBeTruthy();
    }, 15000);

    test('should handle login errors gracefully', async () => {
      await page.goto(`${APP_URL}/login`);
      
      // Try invalid credentials
      await page.waitForSelector('input[name="username"]');
      await page.type('input[name="username"]', 'invaliduser');
      await page.type('input[name="password"]', 'wrongpassword');
      
      await page.click('button[type="submit"]');
      
      // Wait for error message
      await page.waitForSelector('.error-message, [data-testid="error"]', { timeout: 5000 });
      
      const errorText = await page.$eval(
        '.error-message, [data-testid="error"]',
        el => el.textContent
      );
      
      expect(errorText).toContain('Invalid');
      
      // Ensure we're still on login page
      expect(page.url()).toContain('/login');
    });
  });

  describe('Data Management', () => {
    beforeEach(async () => {
      // Login before each test
      await page.goto(`${APP_URL}/login`);
      await page.waitForSelector('input[name="username"]');
      await page.type('input[name="username"]', 'testuser');
      await page.type('input[name="password"]', 'testpass123');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle0' }),
        page.click('button[type="submit"]')
      ]);
    });

    test('should create new data item', async () => {
      await page.goto(`${APP_URL}/data`);
      
      // Click create button
      await page.waitForSelector('[data-testid="create-button"], .btn-create');
      await page.click('[data-testid="create-button"], .btn-create');
      
      // Fill form
      await page.waitForSelector('input[name="name"]');
      await page.type('input[name="name"]', 'Test Item E2E');
      await page.type('textarea[name="description"]', 'Created via E2E test');
      
      // Submit
      await Promise.all([
        page.waitForResponse(response => 
          response.url().includes('/api/data') && response.status() === 201
        ),
        page.click('button[type="submit"]')
      ]);
      
      // Verify item appears in list
      await page.waitForSelector('[data-testid="data-item"]');
      const itemText = await page.$eval('[data-testid="data-item"]', el => el.textContent);
      expect(itemText).toContain('Test Item E2E');
    });

    test('should edit existing data item', async () => {
      await page.goto(`${APP_URL}/data`);
      
      // Wait for data to load and click edit button
      await page.waitForSelector('[data-testid="edit-button"]');
      await page.click('[data-testid="edit-button"]');
      
      // Update the item
      await page.waitForSelector('input[name="name"]');
      await page.evaluate(() => {
        const input = document.querySelector('input[name="name"]') as HTMLInputElement;
        if (input) input.value = '';
      });
      await page.type('input[name="name"]', 'Updated Item E2E');
      
      // Save changes
      await Promise.all([
        page.waitForResponse(response => 
          response.url().includes('/api/data') && response.status() === 200
        ),
        page.click('button[type="submit"]')
      ]);
      
      // Verify update
      const updatedText = await page.$eval('[data-testid="data-item"]', el => el.textContent);
      expect(updatedText).toContain('Updated Item E2E');
    });

    test('should delete data item', async () => {
      await page.goto(`${APP_URL}/data`);
      
      // Count initial items
      await page.waitForSelector('[data-testid="data-item"]');
      const initialCount = await page.$$eval('[data-testid="data-item"]', items => items.length);
      
      // Delete first item
      await page.click('[data-testid="delete-button"]');
      
      // Confirm deletion if modal appears
      const confirmButton = await page.$('[data-testid="confirm-delete"]');
      if (confirmButton) {
        await Promise.all([
          page.waitForResponse(response => 
            response.url().includes('/api/data') && response.status() === 204
          ),
          page.click('[data-testid="confirm-delete"]')
        ]);
      }
      
      // Verify item count decreased
      await page.waitForTimeout(1000); // Wait for UI update
      const finalCount = await page.$$eval('[data-testid="data-item"]', items => items.length);
      expect(finalCount).toBeLessThan(initialCount);
    });
  });

  describe('Performance Tests', () => {
    test('should load pages within acceptable time', async () => {
      const startTime = Date.now();
      
      await page.goto(APP_URL, { waitUntil: 'networkidle0' });
      
      const loadTime = Date.now() - startTime;
      expect(loadTime).toBeLessThan(5000); // Should load within 5 seconds
    });

    test('should handle large data sets efficiently', async () => {
      // Login first
      await page.goto(`${APP_URL}/login`);
      await page.waitForSelector('input[name="username"]');
      await page.type('input[name="username"]', 'testuser');
      await page.type('input[name="password"]', 'testpass123');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle0' }),
        page.click('button[type="submit"]')
      ]);
      
      // Navigate to data page with pagination/filtering
      const startTime = Date.now();
      await page.goto(`${APP_URL}/data?limit=100`);
      await page.waitForSelector('[data-testid="data-list"]');
      
      const loadTime = Date.now() - startTime;
      expect(loadTime).toBeLessThan(10000); // Should handle large sets within 10 seconds
    });
  });

  describe('Error Handling', () => {
    test('should display user-friendly error messages', async () => {
      // Test network error handling
      await page.setOfflineMode(true);
      await page.goto(APP_URL);
      
      // Check for offline indicator or error message
      await page.waitForTimeout(3000);
      const offlineIndicator = await page.$('.offline-indicator, [data-testid="offline"], .error-message');
      expect(offlineIndicator).toBeTruthy();
      
      await page.setOfflineMode(false);
    });

    test('should recover from errors gracefully', async () => {
      await page.goto(APP_URL);
      
      // Simulate a JavaScript error
      await page.evaluate(() => {
        throw new Error('Test error');
      });
      
      // Page should still be functional
      await page.waitForTimeout(1000);
      const isPageResponsive = await page.evaluate(() => {
        return document.readyState === 'complete';
      });
      
      expect(isPageResponsive).toBe(true);
    });
  });

  describe('Security Features', () => {
    test('should prevent XSS in user inputs', async () => {
      // Login first
      await page.goto(`${APP_URL}/login`);
      await page.waitForSelector('input[name="username"]');
      await page.type('input[name="username"]', 'testuser');
      await page.type('input[name="password"]', 'testpass123');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'networkidle0' }),
        page.click('button[type="submit"]')
      ]);
      
      // Try to inject script via form
      await page.goto(`${APP_URL}/data`);
      await page.waitForSelector('[data-testid="create-button"]');
      await page.click('[data-testid="create-button"]');
      
      const xssPayload = '<script>window.xssTriggered = true;</script>';
      await page.waitForSelector('input[name="name"]');
      await page.type('input[name="name"]', xssPayload);
      await page.click('button[type="submit"]');
      
      // Check that script didn't execute
      const xssTriggered = await page.evaluate(() => (window as any).xssTriggered);
      expect(xssTriggered).toBeUndefined();
    });

    test('should enforce HTTPS in production', async () => {
      if (APP_URL.startsWith('https://')) {
        const response = await page.goto(APP_URL);
        expect(response?.status()).toBe(200);
        
        // Check for security headers
        const headers = response?.headers();
        expect(headers?.['strict-transport-security']).toBeDefined();
      }
    });
  });
});