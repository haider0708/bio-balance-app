// À coller dans la console du navigateur, sur une page https://www.barcodelookup.com/<EAN>.
// Le site refuse les requêtes automatiques : on relève la fiche que l’on est en train de lire,
// puis on ajoute le résultat à data/initial-catalog/sources/barcodelookup-capture.json.
(() => {
  const text = document.body.innerText;
  const ean = location.pathname.replace(/\D/g, '');
  const image = [...document.images].map((i) => i.src).find((s) => s.includes('images.barcodelookup.com')) ?? null;
  const out = {
    [ean]: {
      title: document.querySelector('h4')?.innerText ?? null,
      brand: (text.match(/Brand:\s*(.*)/) || [])[1] ?? null,
      image,
    },
  };
  const json = JSON.stringify(out, null, 2);
  navigator.clipboard?.writeText(json).catch(() => {});
  console.log(json);
  return json;
})();
