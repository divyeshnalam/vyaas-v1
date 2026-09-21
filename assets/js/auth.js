// Authentication utilities - Clean slate for fresh frontend build
// This file will be rebuilt as needed for the new frontend

export const Auth = {
  // Store token in localStorage
  storeToken: function(token) {
    localStorage.setItem('auth_token', token);
    console.log('Token stored in localStorage');
  },
  
  // Get token from localStorage
  getToken: function() {
    return localStorage.getItem('auth_token');
  },
  
  // Remove token from localStorage
  removeToken: function() {
    localStorage.removeItem('auth_token');
  }
};

// Export for use in LiveView hooks
window.Auth = Auth;
