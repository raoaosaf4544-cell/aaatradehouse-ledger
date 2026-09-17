const fs = require('fs');
const path = require('path');

function searchFiles(dir) {
    const files = fs.readdirSync(dir);
    for (const file of files) {
        const fullPath = path.join(dir, file);
        if (fs.statSync(fullPath).isDirectory()) {
            searchFiles(fullPath);
        } else if (fullPath.endsWith('.js') || fullPath.endsWith('.mjs')) {
            const content = fs.readFileSync(fullPath, 'utf8');
            const lines = content.split('\n');
            for (let i = 0; i < lines.length; i++) {
                if (/fetch\s*=/.test(lines[i])) {
                    console.log(`${fullPath}:${i+1}: ${lines[i].substring(0, 100)}`);
                }
            }
        }
    }
}

searchFiles('node_modules');
