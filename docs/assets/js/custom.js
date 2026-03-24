// claudetools docs — custom JS

(function() {
  'use strict';

  // ===== Copy button on code blocks =====
  document.querySelectorAll('pre').forEach(function(pre) {
    var btn = document.createElement('button');
    btn.className = 'ct-copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', function() {
      var code = pre.querySelector('code');
      var text = code ? code.textContent : pre.textContent;
      navigator.clipboard.writeText(text).then(function() {
        btn.textContent = 'Copied!';
        btn.classList.add('ct-copied');
        setTimeout(function() {
          btn.textContent = 'Copy';
          btn.classList.remove('ct-copied');
        }, 2000);
      });
    });
    pre.style.position = 'relative';
    pre.appendChild(btn);
  });

  // ===== Smooth sidebar toggle on mobile =====
  var sidebar = document.querySelector('.side-bar');
  var menuBtn = document.querySelector('.site-button[name="menu-button"]');

  if (menuBtn && sidebar) {
    menuBtn.addEventListener('click', function() {
      sidebar.classList.toggle('ct-nav-open');
    });

    // Close sidebar when clicking a link on mobile
    sidebar.querySelectorAll('a').forEach(function(link) {
      link.addEventListener('click', function() {
        if (window.innerWidth < 800) {
          sidebar.classList.remove('ct-nav-open');
        }
      });
    });
  }

  // ===== Cmd+K search focus =====
  document.addEventListener('keydown', function(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      var searchInput = document.querySelector('.search-input');
      if (searchInput) {
        searchInput.focus();
        searchInput.select();
      }
    }
  });

  // ===== Active heading tracking (scroll spy) =====
  var headings = document.querySelectorAll('.main-content h2[id], .main-content h3[id]');
  var tocLinks = document.querySelectorAll('.toc-list a');

  if (headings.length > 0 && tocLinks.length > 0) {
    var observer = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          tocLinks.forEach(function(link) {
            link.classList.remove('ct-toc-active');
          });
          var activeLink = document.querySelector('.toc-list a[href="#' + entry.target.id + '"]');
          if (activeLink) {
            activeLink.classList.add('ct-toc-active');
          }
        }
      });
    }, { rootMargin: '-80px 0px -80% 0px' });

    headings.forEach(function(h) { observer.observe(h); });
  }
})();
