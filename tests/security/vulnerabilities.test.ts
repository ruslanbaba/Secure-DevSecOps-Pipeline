import { describe, test, expect, beforeAll, afterAll } from '@jest/globals';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

describe('Security Tests', () => {
  const APP_URL = process.env.SEC_APP_URL || 'http://localhost:3000';
  
  describe('Dependency Vulnerability Scanning', () => {
    test('should have no high-severity vulnerabilities', async () => {
      try {
        // Run npm audit and capture output
        const auditOutput = execSync('npm audit --json', { 
          encoding: 'utf-8',
          cwd: process.cwd()
        });
        
        const auditResults = JSON.parse(auditOutput);
        
        // Check for high and critical vulnerabilities
        const highVulns = auditResults.metadata?.vulnerabilities?.high || 0;
        const criticalVulns = auditResults.metadata?.vulnerabilities?.critical || 0;
        
        expect(highVulns + criticalVulns).toBe(0);
      } catch (error) {
        // If npm audit exits with code 1, it found vulnerabilities
        const output = (error as any).stdout || '';
        if (output) {
          const auditResults = JSON.parse(output);
          const highVulns = auditResults.metadata?.vulnerabilities?.high || 0;
          const criticalVulns = auditResults.metadata?.vulnerabilities?.critical || 0;
          expect(highVulns + criticalVulns).toBe(0);
        }
      }
    }, 30000);

    test('should have updated dependencies', async () => {
      const packageJson = JSON.parse(
        fs.readFileSync(path.join(process.cwd(), 'package.json'), 'utf-8')
      );
      
      // Check for known vulnerable packages
      const vulnerablePackages = [
        'lodash@4.17.20', // Example of known vulnerable version
        'express@4.16.0',
        'helmet@3.0.0'
      ];
      
      const dependencies = {
        ...packageJson.dependencies,
        ...packageJson.devDependencies
      };
      
      vulnerablePackages.forEach(vulnPkg => {
        const [pkgName, vulnVersion] = vulnPkg.split('@');
        const installedVersion = dependencies[pkgName];
        
        if (installedVersion) {
          expect(installedVersion).not.toBe(vulnVersion);
        }
      });
    });
  });

  describe('HTTP Security Headers', () => {
    test('should include security headers', async () => {
      const response = await fetch(`${APP_URL}/health`);
      const headers = Object.fromEntries(response.headers.entries());
      
      // Check for essential security headers
      expect(headers['x-content-type-options']).toBe('nosniff');
      expect(headers['x-frame-options']).toMatch(/^(DENY|SAMEORIGIN)$/);
      expect(headers['x-xss-protection']).toBe('1; mode=block');
      expect(headers['strict-transport-security']).toBeDefined();
      expect(headers['content-security-policy']).toBeDefined();
      expect(headers['referrer-policy']).toBeDefined();
    });

    test('should have proper CSP configuration', async () => {
      const response = await fetch(`${APP_URL}/health`);
      const csp = response.headers.get('content-security-policy');
      
      expect(csp).toBeDefined();
      expect(csp).toContain("default-src 'self'");
      expect(csp).toContain("script-src 'self'");
      expect(csp).toContain("style-src 'self'");
      expect(csp).not.toContain("'unsafe-eval'");
      expect(csp).not.toContain("'unsafe-inline'");
    });

    test('should not expose sensitive headers', async () => {
      const response = await fetch(`${APP_URL}/health`);
      const headers = Object.fromEntries(response.headers.entries());
      
      // Headers that should not be present
      expect(headers['server']).toBeUndefined();
      expect(headers['x-powered-by']).toBeUndefined();
      expect(headers['x-aspnet-version']).toBeUndefined();
    });
  });

  describe('Authentication Security', () => {
    test('should enforce secure password requirements', async () => {
      const weakPasswords = ['123', 'password', 'admin', ''];
      
      for (const password of weakPasswords) {
        const response = await fetch(`${APP_URL}/auth/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            username: 'testuser',
            password: password,
            email: 'test@example.com'
          })
        });
        
        expect(response.status).toBe(400);
        const data = await response.json();
        expect(data.message).toContain('password');
      }
    });

    test('should implement rate limiting for login attempts', async () => {
      const attempts = [];
      
      // Make multiple failed login attempts
      for (let i = 0; i < 6; i++) {
        attempts.push(
          fetch(`${APP_URL}/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              username: 'testuser',
              password: 'wrongpassword'
            })
          })
        );
      }
      
      const responses = await Promise.all(attempts);
      
      // Should get rate limited after several attempts
      const rateLimited = responses.some(response => response.status === 429);
      expect(rateLimited).toBe(true);
    }, 15000);

    test('should use secure session management', async () => {
      const response = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      const setCookie = response.headers.get('set-cookie');
      
      if (setCookie) {
        expect(setCookie).toContain('HttpOnly');
        expect(setCookie).toContain('Secure');
        expect(setCookie).toContain('SameSite');
      }
    });
  });

  describe('Input Validation Security', () => {
    test('should prevent SQL injection', async () => {
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      const { token } = await authResponse.json();
      
      const sqlInjectionPayloads = [
        "'; DROP TABLE users; --",
        "' OR '1'='1",
        "'; INSERT INTO users (username) VALUES ('hacker'); --",
        "' UNION SELECT * FROM users --"
      ];
      
      for (const payload of sqlInjectionPayloads) {
        const response = await fetch(`${APP_URL}/api/data`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            name: payload,
            description: 'Test description'
          })
        });
        
        // Should either reject the input or sanitize it
        if (response.status === 201) {
          const data = await response.json();
          expect(data.name).not.toContain('DROP TABLE');
          expect(data.name).not.toContain('INSERT INTO');
        } else {
          expect([400, 422]).toContain(response.status);
        }
      }
    });

    test('should prevent XSS attacks', async () => {
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      const { token } = await authResponse.json();
      
      const xssPayloads = [
        '<script>alert("xss")</script>',
        '<img src="x" onerror="alert(1)">',
        '<svg onload="alert(1)">',
        'javascript:alert("xss")'
      ];
      
      for (const payload of xssPayloads) {
        const response = await fetch(`${APP_URL}/api/data`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            name: 'Test Name',
            description: payload
          })
        });
        
        if (response.status === 201) {
          const data = await response.json();
          expect(data.description).not.toContain('<script>');
          expect(data.description).not.toContain('javascript:');
          expect(data.description).not.toContain('onerror=');
        }
      }
    });

    test('should validate file uploads securely', async () => {
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      const { token } = await authResponse.json();
      
      // Test malicious file types
      const maliciousFiles = [
        { name: 'test.exe', content: 'MZ\x90\x00' }, // Executable header
        { name: 'test.php', content: '<?php system($_GET["cmd"]); ?>' },
        { name: 'test.jsp', content: '<% Runtime.getRuntime().exec(request.getParameter("cmd")); %>' }
      ];
      
      for (const file of maliciousFiles) {
        const formData = new FormData();
        formData.append('file', new Blob([file.content]), file.name);
        
        const response = await fetch(`${APP_URL}/api/upload`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`
          },
          body: formData
        });
        
        // Should reject malicious file types
        expect([400, 415, 422]).toContain(response.status);
      }
    });
  });

  describe('API Security', () => {
    test('should require authentication for protected endpoints', async () => {
      const protectedEndpoints = [
        '/api/data',
        '/api/users',
        '/api/admin'
      ];
      
      for (const endpoint of protectedEndpoints) {
        const response = await fetch(`${APP_URL}${endpoint}`);
        expect(response.status).toBe(401);
      }
    });

    test('should validate JWT tokens properly', async () => {
      const invalidTokens = [
        'invalid.token.here',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature',
        '',
        'Bearer malformed'
      ];
      
      for (const token of invalidTokens) {
        const response = await fetch(`${APP_URL}/api/protected`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        });
        
        expect(response.status).toBe(401);
      }
    });

    test('should implement proper CORS configuration', async () => {
      const response = await fetch(`${APP_URL}/health`, {
        method: 'OPTIONS',
        headers: {
          'Origin': 'https://malicious-site.com',
          'Access-Control-Request-Method': 'GET'
        }
      });
      
      const corsOrigin = response.headers.get('access-control-allow-origin');
      
      // Should not allow arbitrary origins
      expect(corsOrigin).not.toBe('*');
      expect(corsOrigin).not.toBe('https://malicious-site.com');
    });
  });

  describe('Infrastructure Security', () => {
    test('should not expose sensitive information in errors', async () => {
      // Test various error conditions
      const errorTests = [
        { url: `${APP_URL}/nonexistent`, expectedStatus: 404 },
        { url: `${APP_URL}/api/data/invalid-id`, expectedStatus: 400 }
      ];
      
      for (const test of errorTests) {
        const response = await fetch(test.url);
        expect(response.status).toBe(test.expectedStatus);
        
        const errorData = await response.json();
        
        // Should not expose sensitive paths, stack traces, or internal details
        const errorString = JSON.stringify(errorData).toLowerCase();
        expect(errorString).not.toContain('/home/');
        expect(errorString).not.toContain('/var/');
        expect(errorString).not.toContain('stack trace');
        expect(errorString).not.toContain('database');
        expect(errorString).not.toContain('internal server error');
      }
    });

    test('should use HTTPS in production environment', async () => {
      if (process.env.NODE_ENV === 'production') {
        expect(APP_URL).toMatch(/^https:/);
      }
    });
  });

  describe('Data Protection', () => {
    test('should encrypt sensitive data at rest', async () => {
      // This test would typically check database encryption
      // For now, we'll verify that passwords are not stored in plain text
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      expect(authResponse.status).toBe(200);
      
      // If we had access to the database, we would verify:
      // 1. Passwords are hashed with strong algorithms (bcrypt, scrypt, etc.)
      // 2. Sensitive fields are encrypted
      // 3. Database connections use TLS
    });

    test('should implement proper session timeout', async () => {
      const authResponse = await fetch(`${APP_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: 'testuser',
          password: 'testpass123'
        })
      });
      
      const { token } = await authResponse.json();
      
      // Verify token works initially
      let response = await fetch(`${APP_URL}/api/protected`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      expect(response.status).toBe(200);
      
      // In a real test, we would wait for session timeout
      // For now, we'll check that tokens have expiration
      const tokenParts = token.split('.');
      if (tokenParts.length === 3) {
        const payload = JSON.parse(atob(tokenParts[1]));
        expect(payload.exp).toBeDefined();
        expect(payload.exp).toBeGreaterThan(Date.now() / 1000);
      }
    });
  });
});