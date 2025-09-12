        echo "🔍 Testing Kerberos setup..."
        
        # Test 1: Check KDC is running
        if docker-compose exec kerberos-kdc ps aux | grep -q krb5kdc; then
          echo "✅ KDC process running"
        else
          echo "❌ KDC not running"
          exit 1
        fi
        
        # Test 2: Test authentication
        if echo "admin123" | docker-compose exec -T kerberos-client kinit admin/admin@EXAMPLE.COM 2>/dev/null; then
          echo "✅ Authentication working"
          docker-compose exec kerberos-client klist | head -3
          docker-compose exec kerberos-client kdestroy
        else
          echo "❌ Authentication failed"
          exit 1
        fi
        
        # Test 3: Check keytab extraction
        if docker-compose exec vault test -f /vault/kerberos/vault.keytab 2>/dev/null; then
          echo "✅ Keytab available to Vault"
        else
          echo "⚠️  Keytab not found in Vault"
        fi
        
        echo "🎉 Kerberos is ready for Vault integration!"     