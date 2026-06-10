// Shared config for the Northstar k6 scenarios.
// All scripts run from inside the `northstar_default` docker network, so service
// hostnames (nop_bu1, nop_bu2, prometheus) resolve directly.

export const BU = {
  bu1: {
    base: 'http://nop_bu1',
    // Product slugs come from scripts/seed-bu1.sql.
    products: ['linen-sofa', 'marble-table-lamp', 'rattan-pendant-light', 'walnut-coffee-table'],
    // Keywords picked to match indexed product names.
    searchTerms: ['sofa', 'lamp', 'table', 'pendant', 'walnut', 'linen'],
  },
  bu2: {
    base: 'http://nop_bu2',
    products: ['27-ultrawide-monitor', 'adjustable-standing-desk', 'cable-management-kit', 'ergonomic-mesh-chair'],
    searchTerms: ['monitor', 'desk', 'chair', 'standing', 'mesh', 'cable'],
  },
};

export function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}
