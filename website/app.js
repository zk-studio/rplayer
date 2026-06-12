// RPlayer Landing Page - Interactive Scripts

document.addEventListener('DOMContentLoaded', () => {
    // 1. Fetch Latest Release from GitHub API
    fetchLatestRelease();

    // 2. Interactive Mockup Video Player Simulation
    initPlayerSimulation();
});

/**
 * Fetches the latest release from the GitHub repository API.
 * Dynamically updates the main download button and tag name.
 */
async function fetchLatestRelease() {
    const repo = 'zk-studio/rplayer';
    const downloadBtn = document.getElementById('primary-download-btn');
    const downloadBtnText = document.getElementById('download-btn-text');
    const badgeText = document.querySelector('.hero-badge .badge-text');

    try {
        const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
            headers: {
                'Accept': 'application/vnd.github.v3+json'
            }
        });

        if (!response.ok) {
            console.warn(`GitHub API returned status: ${response.status}`);
            return;
        }

        const data = await response.json();
        const tagName = data.tag_name || 'v1.0.0';
        const assets = data.assets || [];
        const releaseHtmlUrl = data.html_url || `https://github.com/${repo}/releases`;

        // Find the APK asset
        let apkUrl = releaseHtmlUrl;
        for (const asset of assets) {
            const name = asset.name || '';
            if (name.endsWith('.apk')) {
                apkUrl = asset.browser_download_url || apkUrl;
                break;
            }
        }

        // Update UI elements
        if (downloadBtn && downloadBtnText) {
            downloadBtn.href = apkUrl;
            downloadBtnText.textContent = `下载 Android APK (${tagName})`;
        }

        if (badgeText) {
            badgeText.textContent = `RPlayer ${tagName} 现已正式发布，极速 Rust 驱动`;
        }

        console.log(`Latest version resolved: ${tagName}`);
    } catch (error) {
        console.error('Failed to retrieve latest release info from GitHub:', error);
    }
}

/**
 * Simulates playback interactions on the player mockup.
 */
function initPlayerSimulation() {
    const playBtn = document.querySelector('.play-btn');
    const progressBar = document.querySelector('.progress-filled');
    const progressHandle = document.querySelector('.progress-handle');
    const timeCurrent = document.querySelector('.time-display span:first-child');
    const subtitle = document.querySelector('.player-subtitle');

    if (!playBtn) return;

    let isPlaying = true; // Default is playing (indicated by the pause icon in HTML)
    let progressPercent = 70.8; // Initial progress
    const totalSeconds = 6300; // 01:45:00 in seconds
    let currentSeconds = Math.floor(totalSeconds * (progressPercent / 100)); // 01:14:20
    let playTimer = null;

    // Subtitles array to cycle through
    const subtitlesList = [
        "“这才是我们真正需要捍卫的。”",
        "“为了家族的荣耀与希望，我们绝不退缩。”",
        "“每一行代码，每一个像素，都倾注了极客的情怀。”",
        "“在浩瀚的宇宙中，这艘星舰将带我们驶向未知的星系...”"
    ];
    let subtitleIndex = 0;

    // Start playback simulation on load
    startTimer();

    // Toggle Play/Pause
    playBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (isPlaying) {
            // Switch to PAUSE state (shows play icon)
            isPlaying = false;
            playBtn.innerHTML = `
                <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
                    <path d="M8 5v14l11-7z"/>
                </svg>
            `;
            stopTimer();
            subtitle.style.opacity = '0.5';
        } else {
            // Switch to PLAY state (shows pause icon)
            isPlaying = true;
            playBtn.innerHTML = `
                <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
                    <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>
                </svg>
            `;
            startTimer();
            subtitle.style.opacity = '1';
        }
    });

    function startTimer() {
        if (playTimer) clearInterval(playTimer);
        playTimer = setInterval(() => {
            currentSeconds++;
            if (currentSeconds >= totalSeconds) {
                currentSeconds = 0;
            }

            // Update progress percentage
            progressPercent = (currentSeconds / totalSeconds) * 100;
            progressBar.style.width = `${progressPercent}%`;

            // Update current time display
            timeCurrent.textContent = formatTime(currentSeconds);

            // Cycle subtitles every 5 seconds
            if (currentSeconds % 5 === 0) {
                subtitleIndex = (subtitleIndex + 1) % subtitlesList.length;
                
                // Smooth fade effect
                subtitle.style.transition = 'opacity 0.3s ease';
                subtitle.style.opacity = '0';
                
                setTimeout(() => {
                    subtitle.textContent = subtitlesList[subtitleIndex];
                    subtitle.style.opacity = '1';
                }, 300);
            }
        }, 1000);
    }

    function stopTimer() {
        if (playTimer) {
            clearInterval(playTimer);
            playTimer = null;
        }
    }

    function formatTime(seconds) {
        const hrs = Math.floor(seconds / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        
        const pad = (num) => String(num).padStart(2, '0');
        return `${pad(hrs)}:${pad(mins)}:${pad(secs)}`;
    }
}
