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
            if (content.includes("['fetch']") || content.includes('["fetch"]') || content.includes('fetch =')) {
                console.log(fullPath + " matched!");
            }
        }
    }
}
searchFiles('node_modules');
