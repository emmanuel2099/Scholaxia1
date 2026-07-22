/** Class / Holiday promo packages — Paystack (matches mobile ClassPackagesScreen). */

var CLASS_PACKAGE_SECTIONS = {
  student: [
    {
      title: "One-on-One Classes",
      plans: [
        {
          id: "secondary_standard",
          name: "High School (JSS & SSS) One-on-One Classes",
          price: 50000,
          billing: "₦50,000",
          features: ["3 subjects of choice", "One-on-one with tutor", "Topic-based assessments", "Unlimited Sia AI Tutor"],
        },
      ],
    },
    {
      title: "Scholaxia Holiday Promo Classes",
      plans: [
        {
          id: "holiday_ss_science",
          name: "Senior Secondary SS 1–3 · Science",
          price: 11000,
          billing: "₦11,000 · 5 classes weekly",
          features: ["Maths", "English", "Physics", "Chemistry", "Biology"],
        },
        {
          id: "holiday_ss_art",
          name: "Senior Secondary SS 1–3 · Art",
          price: 11000,
          billing: "₦11,000 · 5 classes weekly",
          features: ["Maths", "English", "Literature", "Government", "CRS/IRS"],
        },
        {
          id: "holiday_ss_commercial",
          name: "Senior Secondary SS 1–3 · Commercial",
          price: 11000,
          billing: "₦11,000 · 5 classes weekly",
          features: ["Maths", "English", "Accounting", "Economics", "Commerce"],
        },
        {
          id: "holiday_jss",
          name: "Junior Secondary JSS 1–3",
          price: 10500,
          billing: "₦10,500 · 5 classes weekly",
          features: ["Maths", "English", "Basic Science", "Civic", "Computer"],
        },
      ],
    },
  ],
  kind: [
    {
      title: "One-on-One Classes",
      plans: [
        {
          id: "nursery_standard",
          name: "Nursery One-on-One Classes",
          price: 50000,
          billing: "₦50,000 / Month",
          features: ["Reading", "Phonics", "Counting", "Fun games", "Parent feedback"],
        },
        {
          id: "primary_standard",
          name: "Primary School One-on-One Classes",
          price: 55000,
          billing: "₦55,000 / Monthly",
          features: ["Mathematics", "Phonics", "English", "Homework", "Progress report"],
        },
      ],
    },
    {
      title: "Holiday Classes",
      plans: [
        {
          id: "holiday_primary",
          name: "Primary Holiday Classes",
          price: 15000,
          billing: "₦15,000",
          features: ["Mathematics", "English language", "Phonics", "Moral values"],
        },
      ],
    },
  ],
};

function cpEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function renderClassPackages(rootId, opts) {
  var el = document.getElementById(rootId);
  if (!el) return;
  opts = opts || {};
  var kidsOnly = !!opts.kidsOnly;
  var holidayOnly = !!opts.holidayOnly;
  var sections = kidsOnly ? CLASS_PACKAGE_SECTIONS.kind : CLASS_PACKAGE_SECTIONS.student;
  if (holidayOnly) {
    sections = sections.filter(function (s) {
      return /holiday/i.test(s.title);
    });
  }

  var html =
    '<div class="sx-page-hero"><h2>' +
    (kidsOnly ? "Kids class packages" : holidayOnly ? "Holiday Promo Classes" : "Class packages") +
    "</h2><p>Pay with Paystack — same packages as the mobile app.</p></div>";

  sections.forEach(function (sec) {
    html += '<h3 style="margin:20px 0 12px">' + cpEsc(sec.title) + "</h3><div class=\"card-grid\">";
    sec.plans.forEach(function (p) {
      html +=
        '<div class="sx-card" style="padding:18px">' +
        "<h3>" + cpEsc(p.name) + "</h3>" +
        "<p><strong>" + cpEsc(p.billing) + "</strong></p>" +
        "<ul style=\"margin:10px 0 14px;padding-left:18px;color:var(--sx-grey)\">" +
        p.features
          .map(function (f) {
            return "<li>" + cpEsc(f) + "</li>";
          })
          .join("") +
        "</ul>" +
        '<button type="button" class="btn-action" onclick="buyClassPackage(\'' +
        cpEsc(p.id) +
        "')\">Pay ₦" +
        Number(p.price).toLocaleString("en-NG") +
        "</button></div>";
    });
    html += "</div>";
  });
  el.innerHTML = html;
}

async function buyClassPackage(packageId) {
  if (!packageId || typeof paystackPurchase !== "function") {
    alert("Payment module not loaded.");
    return;
  }
  try {
    var ok = await paystackPurchase({
      productType: "class_package",
      productId: packageId,
    });
    if (ok) alert("Payment successful! Your class package is active.");
    else alert("Payment was not completed.");
  } catch (e) {
    alert(e.message || "Payment failed.");
  }
}

function loadClassPackagesPage() {
  renderClassPackages("class-packages-root", { holidayOnly: false, kidsOnly: false });
}

function loadHolidayPackagesPage() {
  renderClassPackages("holiday-packages-mount", { holidayOnly: true, kidsOnly: false });
}

function loadKindClassPackagesPage() {
  renderClassPackages("kind-packages-root", { kidsOnly: true });
}

window.renderClassPackages = renderClassPackages;
window.buyClassPackage = buyClassPackage;
window.loadClassPackagesPage = loadClassPackagesPage;
window.loadHolidayPackagesPage = loadHolidayPackagesPage;
window.loadKindClassPackagesPage = loadKindClassPackagesPage;
