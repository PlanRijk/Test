// Application safety budgets are estimates, not provider billing readings.
export function freeBudgetAlert(usage){
  if(!usage)return '';
  const b=usage.automatic_budget||{};
  const ratios=[(usage.database_bytes||0)/(b.max_database_bytes||300000000),
    (b.tick_attempts||0)/(b.max_tick_attempts||10000),
    (b.estimated_worker_egress_bytes||0)/(b.max_worker_egress_bytes||4000000000)];
  if(Math.max(...ratios)<.7)return '';
  return 'Verbruikswaarschuwing: minstens 70% van een app-veiligheidsbudget is bereikt. Controleer het echte gebruik bij Render en Supabase. Bij de veiligheidsgrens pauzeert de automatische handel. Een betaalde uitbreiding vereist jouw toestemming.';
}
