import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildRatingReplyText } from './rating_reply.ts';

Deno.test('تقييم ممتاز يذكر اسم الفني', () => {
  const text = buildRatingReplyText({
    score: 10,
    hasNote: false,
    employeeName: 'كرار',
  });
  assertStringIncludes(text!, '10/10');
  assertStringIncludes(text!, 'كرار');
});

Deno.test('تقييم ممتاز بلا فني لا يترك فراغاً', () => {
  const text = buildRatingReplyText({
    score: 9,
    hasNote: false,
    employeeName: null,
  });
  assertStringIncludes(text!, 'فرحانين برضاك');
});

Deno.test('تقييم متوسط يشكر ويعد بالتحسين', () => {
  const text = buildRatingReplyText({
    score: 7,
    hasNote: true,
    employeeName: 'كرار',
  });
  assertStringIncludes(text!, 'نتحسّن');
});

Deno.test('تقييم ضعيف يعتذر ويعد بالتواصل', () => {
  const text = buildRatingReplyText({
    score: 2,
    hasNote: false,
    employeeName: null,
  });
  assertStringIncludes(text!, 'نعتذر');
  assertStringIncludes(text!, 'يتواصل وياك');
});

Deno.test('ملاحظة بلا رقم تُشكر', () => {
  const text = buildRatingReplyText({
    score: null,
    hasNote: true,
    employeeName: null,
  });
  assertStringIncludes(text!, 'ملاحظتك');
});

Deno.test('رد بلا رقم ولا ملاحظة لا يُرد عليه', () => {
  assertEquals(
    buildRatingReplyText({ score: null, hasNote: false, employeeName: null }),
    null,
  );
});
