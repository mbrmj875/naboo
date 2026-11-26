import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { carPhotoMessages, cleanCarImages, parseCarPhoto } from './car_photo.ts';

Deno.test('car photo: new plate normalized', () => {
  assertEquals(
    parseCarPhoto(
      '{"plate":"14-b-64190","plate_style":"new","odometer":"152,300"}',
    ),
    {
      plate: '14 B 64190',
      plate_style: 'new',
      odometer: 152300,
    },
  );
});

Deno.test('car photo: old plate keeps letter and number, style old', () => {
  assertEquals(
    parseCarPhoto(
      '```json\n{"plate":"R 14212","plate_style":"old","odometer":null}\n```',
    ),
    {
      plate: 'R 14212',
      plate_style: 'old',
      odometer: null,
    },
  );
});

Deno.test('car photo: unsure or garbage becomes null, never a guess', () => {
  assertEquals(
    parseCarPhoto('{"plate":"غير واضحة","plate_style":"new","odometer":-5}'),
    {
      plate: null,
      plate_style: 'unknown',
      odometer: null,
    },
  );
  assertEquals(parseCarPhoto('not json'), {
    plate: null,
    plate_style: 'unknown',
    odometer: null,
  });
  assertEquals(parseCarPhoto('{"plate":null,"odometer":12.5}').odometer, null);
  assertEquals(parseCarPhoto('{"odometer":9000000}').odometer, null);
});

Deno.test('car photo: images validated', () => {
  assertEquals(cleanCarImages([]), 'bad_images');
  assertEquals(cleanCarImages(['a', 'b', 'c']), 'bad_images');
  assertEquals(cleanCarImages(['http://x/y.jpg']), 'bad_image');
  assertEquals(cleanCarImages(['data:image/jpeg;base64,AAA']), [
    'data:image/jpeg;base64,AAA',
  ]);
  const m = carPhotoMessages([
    'data:image/jpeg;base64,A',
    'data:image/jpeg;base64,B',
  ]);
  assertEquals(m.length, 2);
  assertEquals((m[1].content as unknown[]).length, 3);
});
