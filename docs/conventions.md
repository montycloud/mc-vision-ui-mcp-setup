# Vision UI Conventions


## Design Principles

- **Clarity:** Every component should have a single, clear purpose
- **Accessibility:** Full WCAG 2.1 AA compliance
- **Consistency:** Unified design language across all components
- **Flexibility:** Components adapt to different use cases via variants

## Component Naming

- PascalCase for component names: `Button`, `DataGrid`, `DatePicker`
- camelCase for prop names: `onClick`, `pageSize`, `errorMessage`
- kebab-case for CSS class names: `bg-brand-500`, `text-text-default`
- Variant files: `{component-name}-variants.ts` (e.g., `button-variants.ts`)

## Import Pattern

All Vision UI components are imported from the main package:

```tsx
import { Button, Input, DataGrid, Card } from '@montycloud/mc-vision-ui';
```

Never import from internal paths like `@montycloud/mc-vision-ui/components/Button`.

## Prop Conventions

- All boolean props default to `false`
- Size props use: `xs`, `sm`, `md`, `lg`, `xl`
- Variant props are explicit string unions (no free-form strings)
- `children` is always `ReactNode` type
- Event handlers follow React convention: `onEventName`

## Compound Component Pattern

Many components use the compound pattern via `Object.assign()`:

```tsx
// Correct usage
<Button variant="primary">
  <Button.Icon icon={<PlusIcon />} />
  <Button.Text>Add Item</Button.Text>
  <Button.Badge count={3} />
</Button>

// Also valid — simple children
<Button variant="primary">Click me</Button>
```

## Variant System (CVA)

All visual variants are defined using `class-variance-authority`:

- Variant dimensions: `variant`, `size`, `isActive`, etc.
- Default variants are always specified
- Compound variants handle edge cases
- Never override CVA classes with inline styles

## Accessibility Requirements

- All interactive elements must have keyboard support
- ARIA labels required for icon-only buttons
- Color contrast ratio >= 4.5:1 for text
- Focus indicators always visible
- Use semantic HTML elements (`<button>`, `<input>`, not `<div>`)

## Styling Rules

- Use Tailwind CSS utility classes (not inline styles)
- Design tokens are CSS custom properties: `var(--colors-brand-bold)`
- Do NOT mix SCSS modules with Tailwind in new code
- Responsive variants: `sm:`, `md:`, `lg:` prefixes

## Known Inconsistencies

- Some legacy components use SCSS modules alongside Tailwind
- Figma token names differ from Tailwind class names (e.g., Figma "Primary/Blue" = Tailwind `brand-600`)
- DataGrid internally uses ag-grid with custom styling wrappers

## Common Patterns

- **Forms:** Wrap inputs in `<Form>` for validation support
- **Modals:** Use `<Dialog>` for confirmations, `<Modal>` for complex content
- **Loading states:** Most action components support a `loading` prop
- **Error states:** Use `error` prop on form components, `<Alert>` for page-level errors
