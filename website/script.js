/* ==========================================================================
   PowerInfo Landing Page JS - Clean UI Interactions & Release Stats
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  initScrollFallback();
  initFAQAccordion();
  initMobileMenu();
  fetchGitHubReleaseInfo();
});

/* ==========================================================================
   1. Scroll Shrink Header Fallback
   ========================================================================== */
function initScrollFallback() {
  const header = document.querySelector('.header-wrapper');
  if (!header) return;

  // If the browser does not natively support CSS Scroll-Driven Animations
  if (!CSS.supports('(animation-timeline: scroll()) and (animation-range: 0% 100%)')) {
    const checkScroll = () => {
      if (window.scrollY > 80) {
        header.classList.add('scrolled');
      } else {
        header.classList.remove('scrolled');
      }
    };
    
    // Initial check and event listener
    checkScroll();
    window.addEventListener('scroll', checkScroll, { passive: true });
  }
}

/* ==========================================================================
   2. FAQ Accordion Toggle
   ========================================================================== */
function initFAQAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');
  
  faqItems.forEach(item => {
    const questionButton = item.querySelector('.faq-question');
    const answer = item.querySelector('.faq-answer');
    
    questionButton.addEventListener('click', () => {
      const isActive = item.classList.contains('active');
      
      // Close all other items first
      faqItems.forEach(otherItem => {
        if (otherItem !== item && otherItem.classList.contains('active')) {
          otherItem.classList.remove('active');
          otherItem.querySelector('.faq-answer').style.maxHeight = '0px';
        }
      });
      
      if (isActive) {
        item.classList.remove('active');
        answer.style.maxHeight = '0px';
      } else {
        item.classList.add('active');
        // Set height to scrollHeight to allow CSS transition on max-height
        answer.style.maxHeight = `${answer.scrollHeight + 20}px`; // Add extra padding
      }
    });
  });
}

/* ==========================================================================
   3. Mobile Navigation Menu Toggle
   ========================================================================== */
function initMobileMenu() {
  const menuBtn = document.querySelector('.mobile-menu-btn');
  const navMenu = document.querySelector('.nav-menu');
  
  if (!menuBtn || !navMenu) return;
  
  menuBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    navMenu.classList.toggle('open');
    
    // Toggle hamburger icon between ☰ and ✕
    if (navMenu.classList.contains('open')) {
      menuBtn.innerHTML = '✕';
    } else {
      menuBtn.innerHTML = '☰';
    }
  });

  // Close menu when clicking links
  const navLinks = document.querySelectorAll('.nav-link');
  navLinks.forEach(link => {
    link.addEventListener('click', () => {
      navMenu.classList.remove('open');
      menuBtn.innerHTML = '☰';
    });
  });
  
  // Close menu when clicking outside
  document.addEventListener('click', (e) => {
    if (navMenu.classList.contains('open') && !navMenu.contains(e.target) && e.target !== menuBtn) {
      navMenu.classList.remove('open');
      menuBtn.innerHTML = '☰';
    }
  });
}

/* ==========================================================================
   4. Dynamic GitHub Releases Fetcher
   ========================================================================== */
function fetchGitHubReleaseInfo() {
  const downloadCountEl = document.getElementById('gh-download-count');
  const releaseTagEl = document.getElementById('gh-release-tag');
  
  if (!downloadCountEl && !releaseTagEl) return;
  
  const repo = "Ka1bOne/PowerInfo-4-Mac";
  
  fetch(`https://api.github.com/repos/${repo}/releases`)
    .then(res => {
      if (!res.ok) throw new Error('Failed to fetch from GitHub');
      return res.json();
    })
    .then(data => {
      if (!data || data.length === 0) return;
      
      const latestRelease = data[0];
      
      // Update Version Tag
      if (releaseTagEl && latestRelease.tag_name) {
        releaseTagEl.textContent = latestRelease.tag_name;
      }
      
      // Count Total Downloads
      let totalDownloads = 0;
      data.forEach(release => {
        if (release.assets) {
          release.assets.forEach(asset => {
            totalDownloads += (asset.download_count || 0);
          });
        }
      });
      
      // Update Downloads text
      if (downloadCountEl && totalDownloads > 0) {
        downloadCountEl.textContent = `${totalDownloads.toLocaleString()} downloads on GitHub`;
      }
    })
    .catch(err => {
      console.warn("GitHub API error (possibly rate-limited or offline):", err);
      // Fails silently, leaving default tags in HTML
    });
}
