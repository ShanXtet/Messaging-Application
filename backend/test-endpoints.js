import fetch from 'node-fetch';

const BASE_URL = 'http://localhost:4000';

async function testEndpoint(method, endpoint, data = null) {
  try {
    const options = {
      method,
      headers: {
        'Content-Type': 'application/json',
      },
    };
    
    if (data) {
      options.body = JSON.stringify(data);
    }
    
    console.log(`\n[TEST] ${method} ${endpoint}`);
    const response = await fetch(`${BASE_URL}${endpoint}`, options);
    
    console.log(`Status: ${response.status}`);
    console.log(`Content-Type: ${response.headers.get('content-type')}`);
    
    const text = await response.text();
    console.log(`Response body: ${text.substring(0, 200)}${text.length > 200 ? '...' : ''}`);
    
    // Try to parse as JSON
    try {
      const json = JSON.parse(text);
      console.log('✅ Valid JSON response');
    } catch (e) {
      console.log('❌ Invalid JSON response');
      console.log('Error:', e.message);
    }
    
  } catch (error) {
    console.log(`❌ Request failed: ${error.message}`);
  }
}

async function runTests() {
  console.log('🧪 Testing API endpoints...\n');
  
  // Test health endpoint
  await testEndpoint('GET', '/health');
  
  // Test register endpoint
  await testEndpoint('POST', '/api/register', {
    name: 'Test User',
    email: 'test@example.com',
    password: 'password123'
  });
  
  // Test login endpoint
  await testEndpoint('POST', '/api/login', {
    email: 'test@example.com',
    password: 'password123'
  });
  
  // Test non-existent endpoint
  await testEndpoint('GET', '/api/nonexistent');
  
  // Test user discovery endpoints
  console.log('\n🧪 Testing User Discovery endpoints...');
  
  // Test get all users
  await testEndpoint('GET', '/api/users?limit=5');
  
  // Test search users
  await testEndpoint('GET', '/api/users/search?q=test');
  
  // Test get specific user (will fail without auth)
  await testEndpoint('GET', '/api/users/507f1f77bcf86cd799439011');
  
  console.log('\n✅ Tests completed!');
}

runTests().catch(console.error);
