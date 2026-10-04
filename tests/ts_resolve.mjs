// Lets Node load ArkTS-style extensionless imports ("./SessionRules") between .ts files.
import { register } from 'node:module';

register('data:text/javascript,' + encodeURIComponent(`
export async function resolve(specifier, context, next) {
  if (specifier.startsWith('.') && context.parentURL?.endsWith('.ts') && !/\\.[a-z]+$/.test(specifier)) {
    return next(specifier + '.ts', context);
  }
  return next(specifier, context);
}`));
