// school365ai.com's public pages (docs/seo.md, S2).
//
// 1. Old links into the app. The app lived at the site root and routed
//    after a '#', so every link it ever sent - set-password and reset
//    emails, the Play Store listing, bookmarks - reads
//    https://school365ai.com/#/something. A server never sees what follows
//    the '#', so those arrive here; this sends them on to the same screen
//    of the app at /app/. It runs first, in <head>, so the page never
//    flashes on the way, and again on 'hashchange', because an address
//    typed while a page is open changes only the part after the '#'.
//
// 2. The Request a Demo and Join Early Access forms (forms.html): opened
//    from any link to #request-a-demo or #join-early-access, checked here
//    first, then sent to the same API endpoints the app's forms use. What
//    the server refuses is shown beside the field it is about.
(function () {
  function forward() {
    var hash = window.location.hash;
    if (hash.indexOf('#/') === 0) {
      window.location.replace('/app/' + hash);
      return true;
    }
    return false;
  }

  if (forward()) return;
  window.addEventListener('hashchange', function () {
    if (!forward()) openFromHash();
  });

  var FORMS = ['request-a-demo', 'join-early-access'];
  var PHONE = /^\+[1-9][0-9 ]{6,17}$/;
  var EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

  function dialogFor(name) {
    return FORMS.indexOf(name) === -1 ? null : document.getElementById(name);
  }

  function open(name) {
    var dialog = dialogFor(name);
    if (!dialog || dialog.open) return;
    reset(dialog);
    if (typeof dialog.showModal === 'function') {
      dialog.showModal();
    } else {
      dialog.setAttribute('open', '');
    }
    var first = dialog.querySelector('input');
    if (first) first.focus();
  }

  function close(dialog) {
    if (typeof dialog.close === 'function') {
      dialog.close();
    } else {
      dialog.removeAttribute('open');
    }
  }

  function openFromHash() {
    open(window.location.hash.slice(1));
  }

  function reset(dialog) {
    var form = dialog.querySelector('form');
    var done = dialog.querySelector('.form-done');
    form.hidden = false;
    done.hidden = true;
    clearProblems(form);
    var day = form.querySelector('input[type="date"]');
    if (day) day.min = today();
  }

  function today() {
    var now = new Date();
    var month = String(now.getMonth() + 1).padStart(2, '0');
    var date = String(now.getDate()).padStart(2, '0');
    return now.getFullYear() + '-' + month + '-' + date;
  }

  // -- problems --------------------------------------------------------------

  function clearProblems(form) {
    form.querySelectorAll('.field-error').forEach(function (node) { node.remove(); });
    form.querySelectorAll('[aria-invalid]').forEach(function (field) { field.removeAttribute('aria-invalid'); });
    var banner = form.querySelector('.form-problem');
    banner.hidden = true;
    banner.textContent = '';
  }

  function showProblem(form, name, message) {
    var field = form.elements[name];
    if (!field) {
      showBanner(form, message);
      return;
    }
    field.setAttribute('aria-invalid', 'true');
    var note = document.createElement('span');
    note.className = 'field-error';
    note.id = field.id + '-error';
    note.textContent = message;
    field.setAttribute('aria-describedby', note.id);
    field.insertAdjacentElement('afterend', note);
  }

  function showBanner(form, message) {
    var banner = form.querySelector('.form-problem');
    banner.textContent = message;
    banner.hidden = false;
  }

  function check(form) {
    var problems = {};
    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name) return;
      var value = field.value.trim();
      // The caption's own words, without '(optional)' or a hint after them.
      var label = field.closest('label').querySelector('.caption').firstChild.textContent.trim();
      if (field.required && !value) {
        problems[field.name] = label + ' is required.';
      } else if (value && field.name === 'email' && !EMAIL.test(value)) {
        problems[field.name] = 'Enter a valid email address.';
      } else if (value && field.name === 'phone' && !PHONE.test(value)) {
        problems[field.name] = 'Include the country code, like +91 9876543210.';
      } else if (value && field.type === 'number' && !(Number(value) >= 1 && Number(value) <= 200000)) {
        problems[field.name] = 'Enter a number between 1 and 200,000.';
      } else if (value && field.type === 'date' && value < today()) {
        problems[field.name] = 'Pick a day that has not passed.';
      }
    });
    return problems;
  }

  // -- sending -----------------------------------------------------------------

  function payload(form) {
    var body = {};
    Array.prototype.forEach.call(form.elements, function (field) {
      if (!field.name) return;
      var value = field.value.trim();
      if (!value) return;
      body[field.name] = field.type === 'number' ? Number(value) : value;
    });
    if (form.dataset.endpoint === '/demo-requests') {
      try {
        body.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      } catch (error) {
        // An old browser that cannot say: the server then reads the day in
        // the platform's own timezone.
      }
    }
    return body;
  }

  function send(form) {
    var button = form.querySelector('button[type="submit"]');
    var label = button.textContent;
    clearProblems(form);

    var problems = check(form);
    var names = Object.keys(problems);
    if (names.length) {
      names.forEach(function (name) { showProblem(form, name, problems[name]); });
      form.elements[names[0]].focus();
      return;
    }

    button.disabled = true;
    button.textContent = 'Sending...';

    fetch(document.body.dataset.api + form.dataset.endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload(form)),
    })
      .then(function (response) {
        return response.json().catch(function () { return {}; }).then(function (data) {
          return { status: response.status, data: data };
        });
      })
      .then(function (result) {
        if (result.status === 201) {
          var dialog = form.closest('dialog');
          form.reset();
          form.hidden = true;
          var done = dialog.querySelector('.form-done');
          done.querySelector('.done-message').textContent = result.data.message || 'Thank you - we will be in touch.';
          done.hidden = false;
          done.querySelector('button').focus();
          return;
        }
        var errors = (result.data.details && result.data.details.errors) || null;
        if (result.status === 422 && errors) {
          Object.keys(errors).forEach(function (name) { showProblem(form, name, errors[name][0]); });
          showBanner(form, 'Please check the details marked below.');
        } else if (result.status === 429) {
          showBanner(form, 'Too many requests from here just now. Please try again in a few minutes.');
        } else {
          showBanner(form, result.data.message || 'This could not be sent just now. Please try again.');
        }
      })
      .catch(function () {
        showBanner(form, 'This could not be sent - check your connection and try again.');
      })
      .then(function () {
        button.disabled = false;
        button.textContent = label;
      });
  }

  // -- the bar: the Product menu, the phone's menu, the page you are on ----------
  //
  // 3. Both menus are buttons that show and hide a list, and say so with
  //    aria-expanded. Escape or a click elsewhere closes them; following a
  //    link inside closes the phone's menu so the page underneath shows.

  function setOpen(button, panel, isOpen) {
    button.setAttribute('aria-expanded', String(isOpen));
    panel.hidden = !isOpen;
  }

  function wireMenus() {
    var productButton = document.querySelector('[data-menu]');
    var productPanel = productButton && document.getElementById(productButton.getAttribute('aria-controls'));
    var phoneButton = document.querySelector('[data-mobile-menu]');
    var phonePanel = phoneButton && document.getElementById(phoneButton.getAttribute('aria-controls'));

    if (productButton && productPanel) {
      productButton.addEventListener('click', function () {
        setOpen(productButton, productPanel, productPanel.hidden);
      });
      productPanel.addEventListener('click', function (event) {
        if (event.target.closest('a')) setOpen(productButton, productPanel, false);
      });
    }

    if (phoneButton && phonePanel) {
      phoneButton.addEventListener('click', function () {
        var isOpen = phonePanel.hidden;
        setOpen(phoneButton, phonePanel, isOpen);
        phoneButton.setAttribute('aria-label', isOpen ? 'Close the menu' : 'Open the menu');
      });
      phonePanel.addEventListener('click', function (event) {
        if (event.target.closest('a')) {
          setOpen(phoneButton, phonePanel, false);
          phoneButton.setAttribute('aria-label', 'Open the menu');
        }
      });
    }

    document.addEventListener('click', function (event) {
      if (productButton && productPanel && !productPanel.hidden && !event.target.closest('.nav-menu')) {
        setOpen(productButton, productPanel, false);
      }
    });

    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') return;
      if (productPanel && !productPanel.hidden) {
        setOpen(productButton, productPanel, false);
        productButton.focus();
      }
      if (phonePanel && !phonePanel.hidden) {
        setOpen(phoneButton, phonePanel, false);
        phoneButton.focus();
      }
    });

    // The page you are on is marked in the bar.
    var here = window.location.pathname.replace(/\/+$/, '') || '/';
    document.querySelectorAll('.nav-links > a, .mobile-menu a').forEach(function (link) {
      var path = link.getAttribute('href');
      if (path && path.charAt(0) === '/' && path.indexOf('#') === -1 && path.replace(/\/+$/, '') === here) {
        link.setAttribute('aria-current', 'page');
      }
    });
  }

  // -- the homepage's role tabs ---------------------------------------------------
  //
  // 4. The tab pattern: one panel showing, the others hidden; arrow keys,
  //    Home and End move between tabs, as screen-reader users expect.

  function wireTabs() {
    document.querySelectorAll('[role="tablist"]').forEach(function (list) {
      var tabs = Array.prototype.slice.call(list.querySelectorAll('[role="tab"]'));

      function select(tab) {
        tabs.forEach(function (other) {
          var chosen = other === tab;
          other.setAttribute('aria-selected', String(chosen));
          other.tabIndex = chosen ? 0 : -1;
          var panel = document.getElementById(other.getAttribute('aria-controls'));
          if (panel) panel.hidden = !chosen;
        });
      }

      tabs.forEach(function (tab, index) {
        tab.addEventListener('click', function () { select(tab); });
        tab.addEventListener('keydown', function (event) {
          var next = null;
          if (event.key === 'ArrowRight') next = tabs[(index + 1) % tabs.length];
          if (event.key === 'ArrowLeft') next = tabs[(index - 1 + tabs.length) % tabs.length];
          if (event.key === 'Home') next = tabs[0];
          if (event.key === 'End') next = tabs[tabs.length - 1];
          if (next) {
            event.preventDefault();
            select(next);
            next.focus();
          }
        });
      });
    });
  }

  // -- wiring --------------------------------------------------------------------

  document.addEventListener('DOMContentLoaded', function () {
    document.addEventListener('click', function (event) {
      var link = event.target.closest('a[href^="#"]');
      if (link && dialogFor(link.getAttribute('href').slice(1))) {
        event.preventDefault();
        open(link.getAttribute('href').slice(1));
        return;
      }
      var closer = event.target.closest('[data-close]');
      if (closer) {
        close(closer.closest('dialog'));
        return;
      }
      // A click on the dimmed backdrop lands on the dialog itself.
      if (event.target.tagName === 'DIALOG') close(event.target);
    });

    document.querySelectorAll('form.lead-form').forEach(function (form) {
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        send(form);
      });
    });

    wireMenus();
    wireTabs();
    openFromHash();
  });
})();
