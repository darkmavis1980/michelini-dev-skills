// PM2 ecosystem for the production server (non-Docker deploy).
//
// Static apps (SPAs) are not here: nginx serves their dist/ folders and proxies /api/ to
// the server below. See nginx.sample.conf.
//
// On the server, copy this file to ecosystem.config.js (git-ignored), fill in the real
// secrets, then: pm2 startOrReload ecosystem.config.js --update-env && pm2 save
//
// Every key in apps/server/.env.sample must also be here. This file is the only thing that
// injects env in production, so a missing key fails at runtime, not at deploy.

module.exports = {
  apps: [
    {
      name: '<project>-server',
      cwd: 'apps/server',
      script: 'npm',
      args: 'start',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        PORT: 3001,
        DB_HOST: 'localhost',
        DB_PORT: 5432,
        DB_NAME: '<db>',
        DB_USER: '<db>',
        DB_PASSWORD: 'replace-me',
        // Generate with: node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
        JWT_SECRET: 'replace-me',
        ALLOWED_ORIGINS: 'https://<domain>',
      },
    },
    // An SSR frontend (e.g. Next.js `next start`) is a second app block:
    // {
    //   name: '<project>-web',
    //   cwd: 'apps/client',
    //   script: 'npm',
    //   args: 'start',
    //   env: { NODE_ENV: 'production', PORT: 3000, API_BASE_URL: 'http://127.0.0.1:3001/api' },
    // },
  ],
};
