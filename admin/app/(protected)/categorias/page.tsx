import { supabaseAdmin } from "@/lib/supabase-admin";
import ActionForm from "@/components/ActionForm";
import { fetchMerchantCategories } from "@/lib/categories";
import { createCategory, deleteCategory, updateCategory } from "./actions";

export const dynamic = "force-dynamic";

/// Categorias de comercio: en la app, los descuentos y premios se filtran
/// por estas categorias. Cada comercio elige una en su ficha.
export default async function CategoriesPage() {
  const [categories, { data: merchants }] = await Promise.all([
    fetchMerchantCategories(),
    supabaseAdmin().from("partner_merchants").select("category").returns<{ category: string | null }[]>(),
  ]);
  const usage = new Map<string, number>();
  for (const merchant of merchants ?? []) {
    if (merchant.category) usage.set(merchant.category, (usage.get(merchant.category) ?? 0) + 1);
  }

  return (
    <>
      <h1>Categorías de comercio</h1>
      <p className="text-dim">
        En la app, los clientes filtran los descuentos y premios por estas categorías. Cada comercio elige la suya en su
        ficha. El orden decide cómo aparecen (menor primero).
      </p>

      <div className="card">
        <h3>Nueva categoría</h3>
        <ActionForm action={createCategory} className="grid-form" submitLabel="Crear categoría" resetOnSuccess>
          <div className="field">
            <label>Nombre</label>
            <input type="text" name="name" required maxLength={60} placeholder="Restaurantes y cafeterías" />
          </div>
          <div className="field">
            <label>Emoji (opcional)</label>
            <input type="text" name="emoji" maxLength={8} placeholder="🍽️" />
          </div>
          <div className="field">
            <label>Orden</label>
            <input type="number" name="sort_order" min={0} max={999} step={1} defaultValue={50} />
          </div>
        </ActionForm>
      </div>

      <div className="card table-scroll">
        <table>
          <thead>
            <tr>
              <th>Categoría</th>
              <th>Comercios</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {categories.map((category) => (
              <tr key={category.id}>
                <td>
                  <ActionForm action={updateCategory.bind(null, category.id)} className="inline-form" submitLabel="Guardar" inline>
                    <input type="text" name="emoji" maxLength={8} defaultValue={category.emoji ?? ""} style={{ width: 56 }} aria-label="Emoji" />
                    <input type="text" name="name" required maxLength={60} defaultValue={category.name} aria-label="Nombre" />
                    <input
                      type="number"
                      name="sort_order"
                      min={0}
                      max={999}
                      defaultValue={category.sort_order}
                      style={{ width: 80 }}
                      aria-label="Orden"
                    />
                  </ActionForm>
                </td>
                <td>{usage.get(category.name) ?? 0}</td>
                <td>
                  <ActionForm
                    action={deleteCategory.bind(null, category.id)}
                    confirm={`¿Eliminar la categoría “${category.name}”?`}
                    submitLabel="Eliminar"
                    submitClassName="danger"
                    pendingLabel="Eliminando…"
                    inline
                  >
                    {null}
                  </ActionForm>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
